# Gestione Preventivi — Build GitHub Windows + APK

Questo progetto contiene un unico workflow GitHub Actions che avvia **contemporaneamente**:

- **Android APK** → artifact `Gestione-Preventivi-APK`
- **Windows** → artifact `Gestione-Preventivi-Windows`
  - `Gestione-Preventivi-Windows-Portable.zip`
  - `Gestione-Preventivi-Setup.exe`

## Come usarlo

1. Carica il contenuto della cartella del progetto nel repository GitHub.
2. Fai push sul branch `main`, oppure vai in **Actions** e avvia:
   **Build Gestione Preventivi - Windows + APK** → **Run workflow**.
3. I due job partono in parallelo.
4. Quando entrambi terminano, gli artifact sono disponibili nella pagina della run.

Il workflow usa Flutter **3.35.3 stable** e Java **17** per Android.

Sono stati rimossi i due vecchi workflow separati per evitare che lo stesso push generi build duplicate.
