// amiga-run: drives the vAmiga core frame by frame from a command script,
// for analysing Amiga programs without a window. Reads commands from the
// files given (or stdin), one per line; '#' starts a comment.
//
//   config A500_OCS_1MB        machine (vAmiga config scheme)
//   rom FILE                   Kickstart ROM
//   disk N FILE                insert an ADF into dfN
//   power                      switch on and run
//   frames N                   emulate N frames
//   joy PORT ACTION...         up down left right fire release-x release-y
//                              release-fire release (all)
//   mouse PORT left|right [FRAMES]  click a mouse button (default 3 frames)
//   key CODE [FRAMES]          press an Amiga raw key code (hex) for FRAMES (default 3)
//   shot FILE                  screenshot of the last frame as PPM (lores
//                              pixels: 1 x 1 per Amiga lores pixel)
//   dump FILE ADDR LEN         memory to a file (hex address and length)
//   peek ADDR LEN              memory as hex to stdout
//   poke ADDR BYTE...          write bytes
//   regs                       CPU registers
//   until ADDR [MAXFRAMES]     run until the CPU is about to execute ADDR
//   trace ADDR [MAXFRAMES] [COUNT]
//                              run, printing the registers at every visit of ADDR
//   profile N FILE             run N frames, counting the executed instructions
//                              per address; writes "address count" lines
//   watch ADDR [MAXFRAMES] [COUNT]
//                              run, printing the registers whenever the CPU
//                              reads or writes ADDR (PC is the instruction after)
//   record FILE MAXFRAMES COUNT ADDR... START+LEN...
//                              run with breakpoints at the ADDRs; at every hit
//                              (at most COUNT) append a record to FILE: the
//                              address hit (4 bytes), the frame (4), D0-D7 and
//                              A0-A7 (64), then the memory of every range
//                              (big-endian, as in the Amiga). Appends, so
//                              several records can follow each other
//   save FILE / load FILE      snapshots
//   frame                      print the frame counter and beam position
//   echo TEXT                  print TEXT

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <iostream>
#include <sstream>
#include <string>
#include <vector>
#include <map>
#include <functional>
#include <memory>
#include <optional>
#include <format>

#include "vaconfig.h"
#define private public
#define protected public
#include "Emulator.h"
#undef private
#undef protected

using namespace vamiga;

static Emulator *emu;
static Amiga *am;

static u32 num(const std::string &s)
{
    std::string t = s;
    if (!t.empty() && t[0] == '$') t = t.substr(1);
    return (u32)std::stoul(t, nullptr, 16);
}

static void regs(std::ostream &os)
{
    auto &c = am->cpu;
    os << std::format("PC={:06x} SR={:04x} frame={} v={} h={}\n", c.getPC0(), c.getSR(),
                      am->agnus.pos.frame, am->agnus.pos.v, am->agnus.pos.h);
    for (int i = 0; i < 8; i++) os << std::format("D{}={:08x} ", i, c.getD(i));
    os << "\n";
    for (int i = 0; i < 8; i++) os << std::format("A{}={:08x} ", i, c.getA(i));
    os << "\n";
}

// Runs whole frames; returns false if a breakpoint stopped the frame early
static bool runFrame()
{
    // Nobody listens to the emulator's messages; drop them
    Message msg;
    std::exception_ptr ex;
    while (am->msgQueue.get(msg, ex)) { }
    try {
        am->computeFrame();
    } catch (StateChangeException &) {
        am->flags = 0;
        return false;
    }
    return true;
}

static void shot(const std::string &file)
{
    // The stable buffer holds one Texel per hires pixel; take every second
    // one, so one PPM pixel is one lores pixel. The crop is the area a PAL
    // monitor shows: 368 x 287 lores pixels; a standard 320 pixel wide screen
    // (DIWSTRT $2c81) sits at x = 24, y = 18 in it.
    const isize x0 = 2 * 69, x1 = x0 + 2 * 368, y0 = 0x1a, y1 = y0 + 287;
    std::ofstream f(file, std::ios::binary);
    f << "P6\n" << (x1 - x0) / 2 << " " << (y1 - y0) << "\n255\n";
    for (isize y = y0; y < y1; y++) {
        Texel *row = am->denise.pixelEngine.stablePtr(y, 0);
        for (isize x = x0; x < x1; x += 2) {
            u32 rgba = (u32)row[x];
            char px[3] = { (char)(rgba & 0xff), (char)((rgba >> 8) & 0xff), (char)((rgba >> 16) & 0xff) };
            f.write(px, 3);
        }
    }
}

static void joy(int port, const std::string &a)
{
    static const std::map<std::string, GamePadAction> acts = {
        { "up", GamePadAction::PULL_UP }, { "down", GamePadAction::PULL_DOWN },
        { "left", GamePadAction::PULL_LEFT }, { "right", GamePadAction::PULL_RIGHT },
        { "fire", GamePadAction::PRESS_FIRE }, { "release-x", GamePadAction::RELEASE_X },
        { "release-y", GamePadAction::RELEASE_Y }, { "release-fire", GamePadAction::RELEASE_FIRE },
        { "release", GamePadAction::RELEASE_XY },
    };
    auto &p = port == 1 ? am->controlPort1 : am->controlPort2;
    auto it = acts.find(a);
    if (it == acts.end()) throw std::runtime_error("unknown joystick action " + a);
    p.joystick.trigger(it->second);
    if (a == "release") p.joystick.trigger(GamePadAction::RELEASE_FIRE);
}

static void exec(const std::vector<std::string> &w)
{
    const std::string &c = w[0];
    auto arg = [&](size_t i) -> const std::string & {
        if (i >= w.size()) throw std::runtime_error("missing argument for " + c);
        return w[i];
    };
    if (c == "config") {
        auto s = ConfigSchemeEnum::parseEnum(arg(1));
        if (!s) throw std::runtime_error("unknown config " + arg(1));
        am->set(*s);
    } else if (c == "rom") {
        am->mem.loadRom(fs::path(arg(1)));
    } else if (c == "disk") {
        am->df[std::stoi(arg(1))]->swapDisk(fs::path(arg(2)));
    } else if (c == "power") {
        am->powerOn();
        am->run();
        emu->state = ExecState::RUNNING;
    } else if (c == "frames") {
        long n = std::stol(arg(1));
        for (long i = 0; i < n; i++) runFrame();
    } else if (c == "joy") {
        for (size_t i = 2; i < w.size(); i++) joy(std::stoi(arg(1)), w[i]);
    } else if (c == "mouse") {
        // mouse PORT left|right [FRAMES]: click a button
        auto &p = std::stoi(arg(1)) == 1 ? am->controlPort1 : am->controlPort2;
        bool right = arg(2) == "right";
        long n = w.size() > 3 ? std::stol(w[3]) : 3;
        p.mouse.trigger(right ? GamePadAction::PRESS_RIGHT : GamePadAction::PRESS_LEFT);
        for (long i = 0; i < n; i++) runFrame();
        p.mouse.trigger(right ? GamePadAction::RELEASE_RIGHT : GamePadAction::RELEASE_LEFT);
    } else if (c == "key") {
        auto code = (KeyCode)num(arg(1));
        long n = w.size() > 2 ? std::stol(w[2]) : 3;
        am->keyboard.press(code);
        for (long i = 0; i < n; i++) runFrame();
        am->keyboard.release(code);
    } else if (c == "shot") {
        shot(arg(1));
    } else if (c == "dump") {
        u32 a = num(arg(2)), n = num(arg(3));
        std::vector<u8> buf(n);
        am->mem.spypeek<Accessor::CPU>(a, n, buf.data());
        std::ofstream(arg(1), std::ios::binary).write((char *)buf.data(), n);
    } else if (c == "peek") {
        u32 a = num(arg(1)), n = num(arg(2));
        for (u32 i = 0; i < n; i++) {
            if (i % 16 == 0) std::cout << std::format("{}{:06x}:", i ? "\n" : "", a + i);
            std::cout << std::format(" {:02x}", am->mem.spypeek8<Accessor::CPU>(a + i));
        }
        std::cout << "\n";
    } else if (c == "poke") {
        u32 a = num(arg(1));
        for (size_t i = 2; i < w.size(); i++) am->mem.poke8<Accessor::CPU>(a++, (u8)num(w[i]));
    } else if (c == "regs") {
        regs(std::cout);
    } else if (c == "until" || c == "trace") {
        u32 a = num(arg(1));
        long maxf = w.size() > 2 ? std::stol(w[2]) : 1000;
        long count = w.size() > 3 ? std::stol(w[3]) : 1000000;
        auto &bp = am->cpu.debugger.breakpoints;
        bp.setAt(a);
        long hits = 0;
        bool found = false;
        for (long f = 0; f < maxf && !found; ) {
            if (runFrame()) { f++; continue; }
            if (c == "until") { found = true; break; }
            regs(std::cout);
            if (++hits >= count) break;
            // step over the breakpoint and go on
            bp.disableAt(a);
            am->cpu.execute();
            bp.enableAt(a);
        }
        bp.removeAt(a);
        if (c == "until") {
            if (found) regs(std::cout);
            else std::cout << std::format("until {:06x}: not reached\n", a);
        }
    } else if (c == "watch") {
        u32 a = num(arg(1));
        long maxf = w.size() > 2 ? std::stol(w[2]) : 1000;
        long count = w.size() > 3 ? std::stol(w[3]) : 1000000;
        auto &wp = am->cpu.debugger.watchpoints;
        wp.setAt(a);
        long hits = 0;
        for (long f = 0; f < maxf && hits < count; ) {
            if (runFrame()) { f++; continue; }
            regs(std::cout);
            hits++;
        }
        wp.removeAt(a);
    } else if (c == "record") {
        std::ofstream f(arg(1), std::ios::binary | std::ios::app);
        long maxf = std::stol(arg(2)), count = std::stol(arg(3));
        std::vector<u32> addrs;
        std::vector<std::pair<u32, u32>> ranges;
        for (size_t i = 4; i < w.size(); i++) {
            auto plus = w[i].find('+');
            if (plus == std::string::npos) addrs.push_back(num(w[i]));
            else ranges.push_back({ num(w[i].substr(0, plus)), num(w[i].substr(plus + 1)) });
        }
        auto &bp = am->cpu.debugger.breakpoints;
        for (auto a : addrs) bp.setAt(a);
        auto put32 = [&](u32 v) { char b[4] = { (char)(v >> 24), (char)(v >> 16), (char)(v >> 8), (char)v }; f.write(b, 4); };
        long hits = 0;
        for (long fr = 0; fr < maxf && hits < count; ) {
            if (runFrame()) { fr++; continue; }
            u32 pc = am->cpu.getPC0();
            put32(pc);
            put32((u32)am->agnus.pos.frame);
            for (int i = 0; i < 8; i++) put32(am->cpu.getD(i));
            for (int i = 0; i < 8; i++) put32(am->cpu.getA(i));
            for (auto &[st, len] : ranges) {
                std::vector<u8> buf(len);
                am->mem.spypeek<Accessor::CPU>(st, len, buf.data());
                f.write((char *)buf.data(), len);
            }
            hits++;
            bp.disableAt(pc);
            am->cpu.execute();
            bp.enableAt(pc);
        }
        for (auto a : addrs) bp.removeAt(a);
        std::cout << std::format("record: {} records\n", hits);
    } else if (c == "profile") {
        long n = std::stol(arg(1));
        std::map<u32, u64> hist;
        auto target = am->agnus.pos.frame + n;
        while (am->agnus.pos.frame < target) {
            hist[am->cpu.getPC0()]++;
            am->cpu.execute();
            if (am->flags) {
                am->flags = 0;
                Message msg;
                std::exception_ptr ex;
                while (am->msgQueue.get(msg, ex)) { }
            }
        }
        std::ofstream f(arg(2));
        for (auto &[a, cnt] : hist) f << std::format("{:06x} {}\n", a, cnt);
    } else if (c == "save") {
        am->saveSnapshot(fs::path(arg(1)));
    } else if (c == "load") {
        am->loadSnapshot(fs::path(arg(1)));
    } else if (c == "frame") {
        std::cout << std::format("frame {} v={} h={}\n", am->agnus.pos.frame,
                                 am->agnus.pos.v, am->agnus.pos.h);
    } else if (c == "echo") {
        for (size_t i = 1; i < w.size(); i++) std::cout << w[i] << (i + 1 < w.size() ? " " : "\n");
    } else {
        throw std::runtime_error("unknown command " + c);
    }
}

static void runStream(std::istream &in)
{
    std::string line;
    while (std::getline(in, line)) {
        auto h = line.find('#');
        if (h != std::string::npos) line = line.substr(0, h);
        std::istringstream ss(line);
        std::vector<std::string> w;
        // a quoted word may contain spaces (file names)
        std::string t;
        while (ss >> std::ws && !ss.eof()) {
            if (ss.peek() == '"') { ss.get(); std::getline(ss, t, '"'); }
            else ss >> t;
            w.push_back(t);
        }
        if (w.empty()) continue;
        exec(w);
        std::cout.flush();
    }
}

int main(int argc, char **argv)
{
    try {
        emu = new Emulator();
        emu->initialize();
        am = &emu->main;
        if (argc < 2) runStream(std::cin);
        for (int i = 1; i < argc; i++) {
            std::ifstream f(argv[i]);
            if (!f) throw std::runtime_error(std::string("cannot open ") + argv[i]);
            runStream(f);
        }
    } catch (std::exception &e) {
        std::cerr << "amiga-run: " << e.what() << "\n";
        return 1;
    }
    return 0;
}
