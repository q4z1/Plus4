#include <stdio.h>
#include <conio.h>

int main(void) {
    // Bildschirm löschen (eine Funktion aus conio.h)
    clrscr();
    
    // Textfarbe ändern (0 = Schwarz, 1 = Weiß, etc. - je nach System)
    textcolor(1); 
    
    // Klassische Ausgabe auf dem Bildschirm
    printf("hello world!\n");
    printf("c-programmierung fuer\n");
    printf("retro-computer...\n");
    
    // Verhindert, dass das Programm sofort beendet wird 
    // Wartet auf einen Tastendruck
    cgetc(); 
    
    return 0;
}
