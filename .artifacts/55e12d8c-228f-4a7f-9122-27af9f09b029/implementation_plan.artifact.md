# Pain Drawing App Implementation Plan

L'obiettivo è creare un'applicazione Flutter che permetta di colorare una "body chart" precaricata. L'app supporterà il disegno a mano libera con un dito e lo zoom/pan con due dita.

## User Review Required

> [!IMPORTANT]
> L'app richiederà un'immagine della "body chart". Per impostazione predefinita, userò un'URL di segnaposto per un'immagine di esempio. Dovrai sostituirla con il tuo file asset reale o fornirmi il percorso se lo hai già nel progetto.

## Proposed Changes

### [Component Name] UI e Logica di Disegno

Creerò un'architettura basata su `CustomPainter` per il disegno e un `GestureDetector` avanzato per gestire la distinzione tra disegno e navigazione.

#### [MODIFY] [main.dart](file:///C:/Users/corrado.cescon/AndroidStudioProjects/pain_sketcher/lib/main.dart)
Aggiornerò `main.dart` per includere:
- Una classe `PainPoint` per memorizzare le coordinate del disegno.
- Un widget `PainDrawingCanvas` che gestisce lo stato del disegno e le trasformazioni (zoom/pan).
- Un `PainPainter` che renderizza l'immagine di sfondo e i tratti del "pennarello".

### Dettagli Tecnici
- **Tratto Costante**: Il pennarello avrà una dimensione fissa e un'opacità piena, come richiesto.
- **Interazione**:
  - **1 Dito**: Aggiunge punti alla lista dei tratti correnti.
  - **2 Dita (Pinch/Spread)**: Aggiorna la matrice di trasformazione per lo zoom.
  - **2 Dita (Trascinamento)**: Aggiorna la traslazione della visuale.

---

## Verification Plan

### Manual Verification
- Avviare l'app su un emulatore o dispositivo fisico.
- Provare a disegnare con un singolo dito: verificare che il tratto sia fluido e costante.
- Provare a fare pinch-to-zoom con due dita: verificare che l'immagine e il disegno si ingrandiscano/rimpiccioliscano insieme.
- Provare a trascinare con due dita: verificare che la visuale si sposti correttamente.
- Zoomare su un dettaglio e verificare che il disegno rimanga "ancorato" correttamente all'immagine di sfondo.
