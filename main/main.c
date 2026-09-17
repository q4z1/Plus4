#include <stdio.h>
#include <conio.h>

int main(void) {
    // Clear the screen (a function from conio.h)
    clrscr();
    
    // Change the text color (0 = black, 1 = white, etc. - depends on the system)
    textcolor(1); 
    
    // Classic output on the screen
    printf("hello world!\n");
    printf("c-programmierung fuer\n");
    printf("retro-computer...\n");
    
    // Keeps the program from ending right away
    // Waits for a key press
    cgetc(); 
    
    return 0;
}
