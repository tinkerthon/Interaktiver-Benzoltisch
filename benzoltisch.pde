/**
Copyright (c) 2011 Olav Schettler

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

Quelle: http://www.opensource.org/licenses/MIT
*/
/**
 * Benzoltisch im Deutschen Museum in Bonn
 *
 * Implementiert mit einem Teensy 2.0 und 
 * der Arduino 0022-Entwicklungsumgebung
 *
 * 2011-07-25 Olav Schettler <olav@tinkerthon.de>
 * - V1
 * - V2: Korrektur in Kommentaren für Bit 9: D7 statt C0
 * - V3: Scan-Codes mit Bits F0, F1, F4, F5, F6, F7
 * - V4: NEC-Codes wie Button Box
 * - V5: Bits 0,1,4,5,6,7 an Port F sind Ausgänge
 * - V7: Live. Neue Substanzgruppen. IR-Codes sind "long". Wird nach "unbekannt" die selbe Substanz wieder gelegt, wird auch ein einerneutes IR-Signal gesendet. 
 * 
 * Anschlüsse:
 * 
 *  - IR-Diode an C7
 *  - Taster an C6
 *  - Standard-LED an D6
 *  - Ports B0..B7, D7 für neun Reed-Schaltereingänge
 *  - Ports F0..F5 für Auswahl des abgetasteten "C"-Atoms
 * 
 * Anschluss über zweireihige Stiftleisten 5x2 und Flachbandkabel
 * Jede Molekülgruppe des Tisches signalisiert über 9 Reed-Schalter
 * ihre Identität. Über eine Infrarot-Diode wird ein Video 
 * zur identifizierten Substanz gestartet. 
 */

#include <IRremote.h>

int version = 7;
int single_step;
int count = 0;

/*
Bits: 76543210 11110011 = F3
0 1 4 5 6 7

76543210
11111110 - FE
11111101 - FD
11101111 - EF 
11011111 - DF
10111111 - BF
01111111 - 7F
*/

int scan_code[] = {
  0xFE, 0xFD, 0xEF, 0xDF, 0xBF, 0x7F
};

// Nur das aktive Bit ist Ausgang, die anderen sind Eingänge
int dir_code[] = {
  0x01, 0x02, 0x10, 0x20, 0x40, 0x80
};

int module[6]; // die sechs Molekülgruppen an den "C"-Atomen
int substance = 0; // 1..12 - die resultierende Substanz

char* subst_name;

/*
// bekannte Module
#define MOD_H      0x0FE
#define MOD_NH2    0x105
#define MOD_CH3    0x005
//#define MOD_CH3    0x005
#define MOD_NO2_1  0x004
#define MOD_NO2_2  0x104
#define MOD_COOH   0x009
#define MOD_CH3COO 0x108
#define MOD_OH     0x111
#define MOD_C2H3   0x121
#define MOD_COH    0x181
*/

/* V5
// bekannte Module
#define MOD_H      0x101
//#define MOD_NH2    0x105
#define MOD_NH2    0x17D
#define MOD_CH3    0x0F7
#define MOD_NO2_1  0x004
#define MOD_NO2_2  0x104
#define MOD_COOH   0x1EE
//#define MOD_COOH   0x009
#define MOD_CH3COO 0x108
#define MOD_OH     0x111
#define MOD_C2H3   0x121
#define MOD_COH    0x181
*/

// bekannte Module
#define MOD_H      0x101
#define MOD_COOH   0x1EE
#define MOD_NO2_1  0x1F7
#define MOD_NO2_2  0x1F6
#define MOD_NH2    0x0FA
#define MOD_CH3    0x0F7
#define MOD_CH3COO 0x0EF

#define MOD_OH     0x0BF
#define MOD_COH    0x0DF

#define MOD_OCH3    0x0DD

#define MOD_C2H3   0x121


#define MOD_T0     0x1FE
#define MOD_T1     0x1FD
#define MOD_T2     0x1FB
#define MOD_T3     0x1F7
#define MOD_T4     0x1EF
#define MOD_T5     0x1DF
#define MOD_T6     0x1BF
#define MOD_T7     0x17F
#define MOD_T8     0x0FF

/*
 * Klartextnamen für Debug-Ausgabe
 */
struct mod_info {
  int code;
  char* name;
};

#define MODULE_COUNT 19
struct mod_info mod_names[] = {
  { MOD_H, "H" },
  { MOD_NH2, "NH2" },
  { MOD_CH3, "CH3" },
  { MOD_NO2_1, "NO2(1)" },
  { MOD_NO2_2, "NO2(2)" },
  { MOD_COOH, "COOH" },
  { MOD_CH3COO, "CH3COO" },
  { MOD_OH, "OH" },
  { MOD_C2H3, "C2H3" },
  { MOD_COH, "COH" },

  { MOD_OCH3, "OCH3" },

  { MOD_T1, "T1" },
  { MOD_T2, "T2" },
  { MOD_T3, "T3" },
  { MOD_T4, "T4" },
  { MOD_T5, "T5" },
  { MOD_T6, "T6" },
  { MOD_T7, "T7" },
  { MOD_T8, "T8" }
};

/*
 * Baugruppenmuster, Ergebnis-Code und Klartextname
 * der erkannten Substanzen
 */
struct subst_info {
  int modules[6];
  int code;
  char* name;
};

#define SUBST_COUNT 14
struct subst_info subst_names[] = {
  { { MOD_H, MOD_H, MOD_H, MOD_H, MOD_H, MOD_H }, 1, "Benzol" },
  { { MOD_NH2, MOD_H, MOD_H, MOD_H, MOD_H, MOD_H }, 2, "Anilin" },

  { { MOD_CH3, MOD_NO2_1, MOD_H, MOD_NO2_1, MOD_H, MOD_NO2_2 }, 3, "TNT" },
  { { MOD_CH3, MOD_NO2_2, MOD_H, MOD_NO2_1, MOD_H, MOD_NO2_1 }, 3, "TNT" },
  { { MOD_CH3, MOD_NO2_1, MOD_H, MOD_NO2_2, MOD_H, MOD_NO2_1 }, 3, "TNT" },

  { { MOD_CH3, MOD_NO2_1, MOD_H, MOD_NO2_2, MOD_H, MOD_NO2_2 }, 3, "TNT" },
  { { MOD_CH3, MOD_NO2_2, MOD_H, MOD_NO2_1, MOD_H, MOD_NO2_2 }, 3, "TNT" },
  { { MOD_CH3, MOD_NO2_2, MOD_H, MOD_NO2_2, MOD_H, MOD_NO2_1 }, 3, "TNT" },

  { { MOD_COOH, MOD_CH3COO, MOD_H, MOD_H, MOD_H, MOD_H }, 4, "Acetylsalicylsaeure" },

  { { MOD_COOH, MOD_H, MOD_H, MOD_H, MOD_H, MOD_H }, 5, "Benzoesaeure" },
  { { MOD_C2H3, MOD_H, MOD_H, MOD_H, MOD_H, MOD_H }, 6, "Styrol" },
  { { MOD_OCH3, MOD_H, MOD_H, MOD_COH, MOD_H, MOD_OH }, 7, "Vanilin" },
  { { MOD_OH, MOD_H, MOD_H, MOD_H, MOD_H, MOD_H }, 8, "Phenol" },

  { { MOD_COH, MOD_H, MOD_H, MOD_H, MOD_H, MOD_H }, 9, "Benzaldehyd" }
};

/*
 * Infrarot-Codes, die für die erkannten Substanzen gesendet werden
 */
struct nec_info {
  int in;
  long out;
};

#define NEC_COUNT 12
struct nec_info nec_codes[] = {
  { 1, 0xC308F7 },
  { 2, 0xC38877 },
  { 3, 0xC348B7 },
  { 4, 0xC3C837 },
  { 5, 0xC330CF },
  { 6, 0xC3B04F },
  { 7, 0xC3708F },
  { 8, 0xC3F00F },
  { 9, 0xC310EF },
  { 10, 0xC3906F },
  { 11, 0xC350AF },
  { 12, 0xC3D02F }
};

IRsend irsend;

/**
 * Dekodiere Baugruppen-Code in Baugruppen-Namen
 * für Debug-Ausgaben
 */
char*
mod_name(int code) {
  for (int i = 0; i < MODULE_COUNT; i++) {
    if (code == mod_names[i].code) {
      return mod_names[i].name;
    }
  }
  return "(undef)";
}

/**
 * Hier steckt die eigentliche "Intelligenz". Der Vergleich der 
 * Molekülgruppen erfolgt normal (mirror=0) und gespiegelt (mirror=1)
 * in 6 gedrehten Positionen (rotate=0..6), d.h. eine Eingabe wird mit 
 * bis zu 2x6=12 Mustern verglichen.
 * 
 * @returns Code der gefundenen Substanz
 * gleichzeitig wird deren Name auf die serielle Schnittstelle ausgegeben
 */ 
int 
subst_code(int modules[]) {
  for (int i = 0; i < SUBST_COUNT; i++) {

    // normal und gespiegelt
    for (int mirror = 0; mirror < 2; mirror++) {
    
      // ... in 6 gedrehten Positionen 
      for (int rotate = 0; rotate < 6; rotate++) {
        
        int match = 1;
        for (int j = 0; j < 6; j++) {
          int ix;
          /*
           * rotate/modulo: z.B. rotate=3, j=4 => ix=1
           */
          ix = (rotate + j) % 6;

          /*
           * spiegeln: 5 => 0, 4 => 1, 3 => 2, 2 => 3, 1 => 4, 0 => 5
           */
          if (mirror == 1) {
            ix = -1 * ix + 5; 
          }
          
          if (modules[j] != subst_names[i].modules[ix]) {
            // Abbruch dieser Runde, falls eine Baugruppe nicht passt
            match = 0;
            break;
          }
        } // 6 Baugruppen
        
        if (match) {
          // Alle Baugruppen passen
          subst_name = subst_names[i].name;
          return subst_names[i].code;
        }
      } // rotate
    } // mirror
  } // alle Substanzen
  
  //Serial.println("(unbekannt)");
  subst_name = "(unbekannt)";
  return 0;
}

/**
 * Dekodiere Substanz-Code 
 * nach Code zum Senden via Infrarot
 */
long
nec_code(int code) {
  for (int i = 0; i < NEC_COUNT; i++) {
    if (code == nec_codes[i].in) {
      return nec_codes[i].out;
    }
  }
  return 0;
}

/**
 * Standard Arduino setup()
 */
void setup() {
  pinMode(PIN_C6, INPUT_PULLUP); // Taster
  pinMode(PIN_D6, OUTPUT); // LED
  
  // Port F, Bits 0,1,4,5,6,7 sind angeschlossen. Zunächst alles Eingänge
  DDRF = 0x00; // 0xF3
  PORTF = 0x00; // PORT F immer auf LOW. Steuerung über Eingänge
  
  DDRB = 0x00; // Port B, Bits 0..7 sind Eingänge
  PORTB = 0xFF; // Bits 0..7 haben Pullups
  pinMode(PIN_D7, INPUT_PULLUP); // ... zusätzlich D7 als Bit 8

  // Keine analogen Eingänge
  DIDR2 = 0x00; 

  // für Debug-Ausgaben an Computer oder LCD-Display
  Serial.begin(9600);
  hello();
}

void hello() {
  Serial.print("\nBenzoltisch v");
  Serial.println(version);
}

/**
 * Standard Arduino loop()
 */
void loop() {
  /* Debug
  Serial.println("\n--------------------");
  Serial.println(count++);
  delay(1000);
  */
  //delay(100);
  
  // Soll die Abtastung im Einzelschritt erfolgen? 
  if (digitalRead(PIN_C6)) {
    // Taster ist nicht gedrückt
    
    if (single_step) {
      // falls Wechsel, Ausgabe
      hello();
      Serial.println("\nAUTO...");
    }

    single_step = 0;
    digitalWrite(PIN_D6, LOW); // LED aus
  }
  else {
    // Taster ist gedrückt
    single_step = 1;
    digitalWrite(PIN_D6, HIGH); // LED an

    // Warten auf Loslassen des Tasters
    while (!digitalRead(PIN_C6)) { delay(50); }
  }
  
  for (int i = 0; i < 6; i++) {
    module[i] = 0;
  }

  if (single_step) {
    hello();
    Serial.println("\nSINGLE:");
  }
  
  /*
   * Abtasten von sechs Baugruppen.
   * Jede Baugruppe schaltet 9 Signale über Reed-Schalter
   */
  for (int step = 0; step < 6; step++) {
    // nur die aktive Spalte is Ausgang, alle anderen sind als Eingang geschaltet
    DDRF = dir_code[step];
    
    // schreibe Spalte
    //PORTF = scan_code[step]; // ein Bit von 6 ist LOW
    
    if (single_step) {
      while (digitalRead(PIN_C6)) { delay(50); }
    }
    else {
      // Kurze Wartezeit, bis sich Pegel aufgebaut haben
      delay(50);
    }
    
    /*
     * lese Zeile
     */
    if (single_step) {
      Serial.print(step);
      Serial.print(" PORTB direkt ");
      Serial.print(PINB, BIN);
      Serial.print(", Bit 9: ");
      Serial.println(digitalRead(PIN_D7), BIN);
    }
     
    module[step] = PINB;    

    // Setze Bit 8 durch separates Lesen von D7
    if (digitalRead(PIN_D7)) {
      module[step] |= 0x100;
    }
    else {
      module[step] &= 0xFF;
    }
  
    if (single_step) {
      Serial.print(step);
      Serial.print(" = ");
      Serial.println(module[step], BIN);
      
      for (int blink = step; blink >= 0; blink--) {
        // Kurzes Zwinkern der LED für (aktuelle Schrittzahl) Mal
        digitalWrite(PIN_D6, LOW); // LED aus
        delay(300);
        digitalWrite(PIN_D6, HIGH); // LED an
        delay(100);
      }
      // Warten auf Loslassen
      while (!digitalRead(PIN_C6)) { delay(50); }
    } // single_step
  } // step
  
  if (single_step) {
    Serial.println("Ergebnis:");
    
    //Serial.print("Test: H=");    
    //Serial.println(mod_name(0x101));
    
    for (int i = 0; i < 6; i++) {
      Serial.print(i);
      Serial.print(": ");
      Serial.print(module[i], BIN);
      Serial.print(" ");
      Serial.println(mod_name(module[i]));
    }
  }
  
  int code = subst_code(module);
  
  // Falls bekannt und geändert. In jedem Fall bei Single Step
  if (single_step || /*code > 0 &&*/ substance != code) {
    long ir_code = nec_code(code);

    Serial.print("Neu! ");
    Serial.print(subst_name);
    Serial.print(", Code: ");
    Serial.print(code);
    Serial.print(", IR-Code: ");
    Serial.println(ir_code, HEX);

    if (ir_code > 0) {
      irsend.sendNEC(ir_code, 32);
    }
  /*
    // Richtig oft senden, damit Spieler das SIgnal mitbekommt
    for (int i = 0; i < 100; i++) {
      irsend.sendNEC(ir_code, 32);
    }  
  */

    substance = code;
  }
} // loop

