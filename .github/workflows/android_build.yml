name: Build Android App

on:
  workflow_dispatch:

jobs:
  build:
    runs-on: ubuntu-latest

    steps:
      - name: Checkout Code
        uses: actions/checkout@v4

      - name: Set up JDK 17
        uses: actions/setup-java@v4
        with:
          distribution: 'zulu'
          java-version: '17'

      - name: Set up Flutter
        uses: subosito/flutter-action@v2
        with:
          channel: 'stable'

      - name: Clean and Get Packages
        run: |
          flutter clean
          flutter pub get

      - name: Create Secrets Files
        env:
          DATA: ${{ secrets.GOOGLE_SERVICES_JSON_BASE64 }}
          KEYSTORE_DATA: ${{ secrets.ANDROID_KEYSTORE_BASE64 }}
        run: |
          # فك تشفير الملفات
          echo "$DATA" | tr -d '[:space:]' | base64 -d > android/app/google-services.json
          echo "$KEYSTORE_DATA" | tr -d '[:space:]' | base64 -d > android/app/upload-keystore.jks

      - name: Build APK
        env:
          STORE_PASSWORD: ${{ secrets.STORE_PASSWORD }}
          KEY_PASSWORD: ${{ secrets.KEY_PASSWORD }}
          KEY_ALIAS: ${{ secrets.KEY_ALIAS }}
          # ✅ جلب السر من GitHub Secrets إلى متغير بيئة
          APP_SECRET: ${{ secrets.APP_SECRET }} 
        run: |
          # ✅ تمرير السر إلى Flutter أثناء البناء باستخدام --dart-define
          flutter build apk --release --dart-define=APP_SECRET="$APP_SECRET"

      - name: Upload APK
        uses: actions/upload-artifact@v4
        with:
          name: release-apk
          path: build/app/outputs/flutter-apk/app-release.apk
