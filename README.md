# Preventivi

App Flutter per gestione di clienti, prodotti/servizi, preventivi, IVA, acconti.

## Build APK su GitHub Actions

1. Carica il contenuto di questo progetto nel repository.
2. Vai in **Actions**.
3. Seleziona **Build Preventivi APK**.
4. Premi **Run workflow**.
5. Al termine apri l'artifact **Preventivi-APK** e scarica `app-release.apk`.

## Build iOS firmata e upload TestFlight/App Store

Il workflow `.github/workflows/build-ios.yml` crea una build iOS firmata e, se i secret sono configurati, carica automaticamente l'IPA su App Store Connect.

### Secret GitHub da creare

Repository → Settings → Secrets and variables → Actions → New repository secret:

- `IOS_BUNDLE_IDENTIFIER` — Bundle ID registrato su Apple Developer, ad esempio `it.tuodominio.preventivi`
- `APPLE_TEAM_ID` — Team ID Apple Developer
- `BUILD_CERTIFICATE_BASE64` — certificato iOS Distribution in formato `.p12`, codificato Base64
- `P12_PASSWORD` — password del file `.p12`
- `BUILD_PROVISION_PROFILE_BASE64` — provisioning profile App Store in Base64
- `KEYCHAIN_PASSWORD` — password casuale per il keychain temporaneo di GitHub Actions
- `APP_STORE_CONNECT_KEY_ID` — Key ID della API Key App Store Connect
- `APP_STORE_CONNECT_ISSUER_ID` — Issuer ID della API Key App Store Connect
- `APP_STORE_CONNECT_API_KEY_BASE64` — file `AuthKey_XXXXXXXXXX.p8` codificato Base64

Il Bundle ID deve corrispondere esattamente al provisioning profile e all'app registrata in App Store Connect. Apple richiede un Apple Developer Program per distribuire l'app; il workflow usa un runner macOS e il certificato/provisioning profile per la firma. Dopo l'upload, il build appare in App Store Connect e può essere distribuito tramite TestFlight o sottoposto all'App Store.


## Build Windows

Il progetto include il workflow `.github/workflows/build-windows.yml`.

Il workflow:
1. prepara automaticamente il progetto Windows;
2. installa le dipendenze;
3. esegue l'analisi;
4. crea la build Windows Release;
5. produce un archivio portatile;
6. crea `Gestione-Preventivi-Setup.exe` con Inno Setup.

In GitHub: **Actions → Build Preventivi Windows → Run workflow**.
Al termine scarica l'artifact **Gestione-Preventivi-Windows**.

La versione Windows utilizza SQLite tramite FFI, quindi mantiene il database locale dell'app senza richiedere un server.


### Scheda Parrocchia – PDF
La scheda tecnica della parrocchia, collegata al cliente, dispone del pulsante **SCARICA PDF**. Il PDF comprende dati della parrocchia e del cliente, impianto audio, campane e note/ultimi interventi. Su Windows viene salvato automaticamente nella cartella Download e aperto al termine della generazione.


## Schede intervento con calcolo costi

Dalla schermata principale è disponibile la sezione **Schede Intervento**. Ogni scheda collega una parrocchia già presente in Clienti e registra data, distanza di sola andata da Via Ugo Pirro 9 a Salerno, prezzo del gasolio al litro, consumo medio del veicolo (litri/100 km), descrizione dell'intervento, ricambi con quantità e costo unitario, ore per tecnico, numero di tecnici e costo orario per tecnico.

Il costo carburante viene calcolato su andata e ritorno; la manodopera è calcolata come ore per tecnico × numero tecnici × costo orario. Il PDF riporta i dati della parrocchia, l'intervento, il dettaglio dei ricambi e il riepilogo di carburante, ricambi, manodopera e totale. Dopo il salvataggio si apre la condivisione del PDF; il PDF può essere rigenerato anche dalla scheda già salvata.

La versione database è stata aggiornata a 18: all'avvio l'app migra automaticamente il database esistente senza cancellare le schede, i clienti o i preventivi precedenti. La versione app è stata incrementata a 1.2.0+4 per consentire l'aggiornamento sopra l'installazione precedente.
