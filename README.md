# Preventivi

App Flutter per gestione di clienti, prodotti/servizi, preventivi, IVA, rate e notifiche.

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
