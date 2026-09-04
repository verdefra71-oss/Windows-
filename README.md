# Preventivi – pacchetto Windows professionale

Questo pacchetto aggiunge una pipeline GitHub Actions per creare:

- `Preventivi-Setup.exe` – installer Windows professionale con Inno Setup;
- `Preventivi-Windows-Portable.zip` – pacchetto portatile pulito.

## Struttura

- `.github/workflows/build-windows-installer.yml` – build Flutter Windows x64 + installer.
- `installer/Preventivi.iss` – configurazione Inno Setup.
- `assets/app_icon.ico` – icona Windows convertita in vero ICO.
- `assets/logo.png` – logo ricodificato in vero PNG.

## Uso

Copia questi file nella radice del repository Flutter e fai push sul branch `main`, oppure avvia manualmente l'azione **Build Preventivi Windows Installer** da GitHub Actions.

Il workflow usa Flutter 3.47.2, compila Windows x64, verifica la presenza dell'EXE e genera l'installer.

Il database `preventivi_full.db` non viene incluso nell'installer: l'app lo crea nella directory dati dell'app tramite `getDatabasesPath()`. Questo evita di distribuire dati locali e soprattutto evita di rendere il database installato in `Program Files` non scrivibile.
