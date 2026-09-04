# Preventivi – pacchetto completo Windows

Questo repository contiene il progetto Flutter minimo necessario per compilare Preventivi per Windows e creare automaticamente installer e versione portatile.

Struttura richiesta nella radice:
- `pubspec.yaml`
- `lib/main.dart`
- `assets/logo.png`
- `.github/workflows/build-windows-installer.yml`
- `installer/Preventivi.iss`

In GitHub: **Actions → Build Preventivi Windows Installer → Run workflow**.

Gli artifact prodotti sono:
- `Preventivi-Setup.exe`
- `Preventivi-Windows-Portable.zip`
