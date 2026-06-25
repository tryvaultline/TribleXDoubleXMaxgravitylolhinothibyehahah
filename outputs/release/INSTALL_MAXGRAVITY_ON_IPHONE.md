# Installing Maxgravity on iPhone (SideStore Guide)

This guide explains how to install the unsigned **Maxgravity** iOS companion application on your physical iPhone using **SideStore**. SideStore is an on-device signing tool that allows you to sideload apps using your own Apple ID without needing a paid developer account.

---

## Prerequisites

Before starting, make sure you have:
1. **SideStore** installed on your iPhone. (If you don't have it yet, follow the official installation guide at [sidestore.io](https://sidestore.io/)).
2. An active Wi-Fi connection with the **SideStore WireGuard VPN** enabled on your iPhone.
3. The built release IPA file: `Maxgravity-1.0-SideStore.ipa`.

---

## Installation Steps

### Step 1: Transfer the IPA to your iPhone
Transfer `Maxgravity-1.0-SideStore.ipa` to your iPhone using one of the following methods:
* **AirDrop**: AirDrop the file directly from your computer to your iPhone, then select **Files** as the destination.
* **iCloud Drive / Files App**: Copy the file into your iCloud Drive or another cloud service, and verify it is accessible from the native **Files** app on iOS.
* **Local Web Server**: Send it via a local network sharing link.

### Step 2: Sideload with SideStore
1. Open the **SideStore** app on your iPhone.
2. Tap the **My Apps** tab at the bottom of the screen.
3. Tap the **+** (plus) icon in the top-left corner.
4. Browse and select the **`Maxgravity-1.0-SideStore.ipa`** file you transferred in Step 1.
5. If prompted, enter your Apple ID and password (these are processed locally or securely sent to the configured Anisette server to request a signing certificate).
6. Wait for the signing process to complete. SideStore will display a progress bar. Once completed, the **Maxgravity** app icon will appear in the installed list.

### Step 3: Trust the Developer Profile (First Time Only)
If this is the first app you are sideloading under this Apple ID, you will receive an "Untrusted Developer" error when launching the app. To fix this:
1. Open the native iOS **Settings** app.
2. Go to **General** > **VPN & Device Management**.
3. Under the **Developer App** section, tap your Apple ID email.
4. Tap **Trust "[your-email]"** and confirm.

---

## Connection and Pairing

Once the app is launched:
1. Turn on the **Maxgravity Bridge** on your Windows computer (`npm run dev` or launch the build executable).
2. Scan the displayed QR code on the desktop using the scan button on the app's first-launch screen.
3. Once paired, you can access your Spaces, task lists, and chats directly from your phone.
