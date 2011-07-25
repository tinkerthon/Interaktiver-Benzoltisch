/**
 * Benzoltisch im Deutschen Museum in Bonn
 *
 * Implementiert mit einem Teensy 2.0 und 
 * der Arduino 0022-Entwicklungsumgebung
 *
 * 2011-07-25 Olav Schettler <olav@tinkerthon.de>
 * - V1.0
 * - V1.1: Korrektur in Kommetaren für Bit 9: D7 statt C0
 * 
 * Anschlüsse:
 * 
 *  - IR-Diode an C7
 *  - Taster an C6
 *  - Standard-LED an D6
 *  - Ports B0..B7, D7 für neun Reed-Schaltereingänge
 *  - Ports F0..F5 für Auswahl des abgetasteten "C"-Atoms
 */

#include <IRremote.h>

int single_step;

int scan_code[] = {
  0x3E, 0x3D, 0x3B, 0x37, 0x2F, 0x1F
};

int module[6]; // die sechs Molekülgruppen an den "C"-Atomen
int substance = 0; // 1..12 - die resultierende Substanz

// bekannte Module
#define MOD_H      0x0FE
#define MOD_NH2    0x105
#define MOD_CH3    0x005
#define MOD_NO2_1  0x004
#define MOD_NO2_2  0x104
#define MOD_COOH   0x009
#define MOD_CH3COO 0x108
#define MOD_OH     0x111
#define MOD_C2H3   0x121
#define MOD_COH    0x181
#define MOD_TRALLA 0x1E1

/*
 * Klartextnamen für Debug-Ausgabe
 */
struct mod_info {
  int code;
  char* name;
};

#define MODULE_COUNT 11
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
  { MOD_TRALLA, "TRALLA" }
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

#define SUBST_COUNT 10
struct subst_info subst_names[] = {
  { { MOD_H, MOD_H, MOD_H, MOD_H, MOD_H, MOD_H }, 1, "Benzol" },
  { { MOD_NH2, MOD_H, MOD_H, MOD_H, MOD_H, MOD_H }, 2, "Anilin" },
  { { MOD_COOH, MOD_CH3COO, MOD_H, MOD_H, MOD_H, MOD_H }, 3, "Acetylsalicylsaeure" },
  { { MOD_CH3, MOD_NO2_1, MOD_H, MOD_NO2_2, MOD_H, MOD_NO2_2 }, 4, "TNT" },
  { { MOD_CH3, MOD_NO2_2, MOD_H, MOD_NO2_1, MOD_H, MOD_NO2_2 }, 4, "TNT" },
  { { MOD_CH3, MOD_NO2_2, MOD_H, MOD_NO2_2, MOD_H, MOD_NO2_1 }, 4, "TNT" },
  { { MOD_COOH, MOD_H, MOD_H, MOD_H, MOD_H, MOD_H }, 5, "Benzoesaeure" },
  { { MOD_OH, MOD_H, MOD_H, MOD_H, MOD_H, MOD_H }, 6, "Phenol" },
  { { MOD_C2H3, MOD_H, MOD_H, MOD_H, MOD_H, MOD_H }, 7, "Styrol" },
  { { MOD_COH, MOD_H, MOD_H, MOD_H, MOD_H, MOD_H }, 8, "Benzaldehyd" }
};

/*
 * Infrarot-Codes, die für die erkannten Substanzen gesendet werden
 * 12 Bits rückwärts, 7 Bit Code + 5 Bit Device. Device=1: Television
 * 1000.00|10.0000
 * 0100.00|10.0000
 * 1100.00|10.0000
 * 0010.00|10.0000
 * 1010.00|10.0000
 * 0110.00|10.0000
 * 1110.00|10.0000
 * 0001.00|10.0000
 * 1001.00|10.0000
 * 0101.00|10.0000
 * 1101.00|10.0000
 * 0011.00|10.0000
 * 1011.00|10.0000
 */
struct sony_info {
  int in;
  int out;
};

#define SONY_COUNT 12
struct sony_info sony_codes[] = {
  { 1, 0x820 },
  { 2, 0x420 },
  { 3, 0xC20 },
  { 4, 0x220 },
  { 5, 0xA20 },
  { 6, 0x620 },
  { 7, 0xE20 },
  { 8, 0x120 },
  { 9, 0x920 },
  { 10, 0x520 },
  { 11, 0xD20 },
  { 12, 0xB20 }
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
          Serial.println(subst_names[i].name);
          return subst_names[i].code;
        }
      } // rotate
    } // mirror
  } // alle Substanzen
  
  Serial.println("(unbekannt)");
  return 0;
}

/**
 * Dekodiere Substanz-Code 
 * nach Code zum Senden via Infrarot
 */
int
sony_code(int code) {
  for (int i = 0; i < SONY_COUNT; i++) {
    if (code == sony_codes[i].in) {
      return sony_codes[i].out;
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
  
  DDRF = 0x3F; // Port F, Bits 0..5 sind Ausgänge
  DDRB = 0x00; // Port B, Bits 0..7 sind Eingänge
  PORTB = 0xFF; // Bits 0..7 haben Pullups
  pinMode(PIN_D7, INPUT_PULLUP); // ... zusätzlich D7 als Bit 8

  // Keine analogen Eingänge
  DIDR2 = 0x00; 

  // für Debug-Ausgaben an Computer oder LCD-Display
  Serial.begin(9600);
}

/**
 * Standard Arduino loop()
 */
void loop() {
  // Soll die Abtastung im Einzelschritt erfolgen? 
  if (digitalRead(PIN_C6)) {
    // Taster ist nicht gedrückt
    
    if (single_step) {
      // falls Wechsel, Ausgabe
      Serial.println("\nAUTO...");
    }

    single_step = 0;
    digitalWrite(PIN_D6, LOW); // LED aus
  }
  else {
    // Taster ist gedrückt
    single_step = 1;
    digitalWrite(PIN_D6, HIGH); // LED an
  }
  
  // Warten auf Loslassen des Tasters
  while (!digitalRead(PIN_C6)) { delay(50); }

  for (int i = 0; i < 6; i++) {
    module[i] = 0;
  }

  if (single_step) {
    Serial.println("\nSINGLE:");
  }
  
  /*
   * Abtasten von sechs Baugruppen.
   * Jede Baugruppe schaltet 9 Signale über Reed-Schalter
   */
  for (int step = 0; step < 6; step++) {
    // schreibe Spalte
    PORTF = scan_code[step]; // ein Bit von 6 ist LOW
    
    if (single_step) {
      while (digitalRead(PIN_C6)) { delay(50); }
    } 
    
    /*
     * lese Zeile
     */
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
    for (int i = 0; i < 6; i++) {
      Serial.print(i);
      Serial.print(": ");
      Serial.print(module[i], BIN);
      Serial.print(" ");
      Serial.println(mod_name(module[i]));
    }
  }
  
  int code = subst_code(module);
  
  // falls bekannt und geändert
  if (code > 0 && substance != code) {
    int ir_code = sony_code(code);

    for (int i = 0; i < 3; i++) {
      irsend.sendSony(ir_code, 12);
      delay(100);
    }
    substance = code;
  }
} // loop

