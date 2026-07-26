# OBDLink MX+ hardware acceptance

This runbook separates adapter arrival, operating-system pairing, adapter-only
communication, and real-vehicle communication. Passing one stage is not evidence
that a later stage passed.

## Safety boundary

- Confirm the product label says `OBDLink MX+`. Do not treat MX, LX, CX, or an
  unverified clone as equivalent.
- Power the adapter only from a manufacturer-approved source. Vehicle power,
  ignition changes, firmware updates, VIN requests, and PID acquisition require
  explicit human approval at the time of execution.
- Do not run the OBDLink app and ProjectZD8 against the adapter concurrently.
- Do not paste the Bluetooth address, VIN, serial number, or Raw response into a
  public issue. Store evidence locally.

## Evidence stages

| Stage | Pass condition | Does not prove |
| --- | --- | --- |
| Package identity | Product label is exactly OBDLink MX+ | Radio, firmware, or vehicle communication |
| OS pairing | MX+ is paired in the operating system | ProjectZD8 communication |
| macOS adapter smoke test | RFCOMM opens and `ATI` returns a non-error response | VIN, PID, or vehicle compatibility |
| ProjectZD8 vehicle identification | `0902` returns a valid observed identifier | Continuous PID collection |
| PID acquisition | Allowed configured PIDs produce Raw-backed observations | Visual approval or long-session stability |

## macOS arrival procedure

1. Power the MX+ using the approved source, press its physical Connect button,
   and complete pairing in macOS System Settings within the manufacturer’s
   pairing window.
2. Confirm that the paired device is visible locally:

   ```sh
   system_profiler SPBluetoothDataType -json | rg -i -C 4 'OBDLink|MX\+'
   ```

3. Obtain the paired Bluetooth address from the local system information. Keep
   it local, then run only the opt-in adapter smoke test:

   ```sh
   PROJECTZD8_MXPLUS_ADDRESS='PAIRED-DEVICE-ADDRESS' \
   xcodebuild \
     -project ProjectZD8.xcodeproj \
     -scheme ProjectZD8 \
     -destination 'platform=macOS' \
     -derivedDataPath /tmp/ProjectZD8-mxplus-hardware \
     -skip-testing:ProjectZD8UITests \
     -only-testing:ProjectZD8Tests/MacOSBluetoothRFCOMMOBDTransportHardwareTests \
     test
   ```

   This test dynamically resolves the standard Serial Port Profile, opens
   RFCOMM, and sends only `ATI`. It does not request VIN or PID data. Without
   `PROJECTZD8_MXPLUS_ADDRESS`, the test is skipped.

4. In ProjectZD8 Settings, select Bluetooth and refresh. A paired device named
   `OBDLink MX+` or `OBDLink MX+ <suffix>` must appear. Unpaired devices and
   other OBDLink models must not appear as MX+ candidates.
5. Stop after adapter selection unless real-vehicle identification has been
   explicitly approved. HOME connection proceeds beyond the adapter-only test
   and may send `ATZ`, configuration commands, `ATI`, `0902`, and `ATDP`.

When reporting a failure, record the first visible diagnostic stage:
`ENDPOINT`, `TRANSPORT-CREATE`, `TRANSPORT-OPEN`, `ATZ`, `AT-CONFIG`, `ATI`,
`0902-REQUEST`, `0902-PARSE`, or `ATDP`. Do not substitute a later inferred
cause for the first observed failure.

## iPhone arrival procedure and external stop condition

1. Power the MX+ using the approved source, press its physical Connect button,
   and pair `OBDLink MX+` in iPhone Settings. The MX+ uses Bluetooth Classic,
   so a CoreBluetooth BLE scan is not proof of MX+ availability.
2. The official OBDLink app may be used separately to confirm the adapter and
   iPhone can pair. Close it before ProjectZD8 testing. Its success is not
   ProjectZD8 evidence.
3. Do not add a guessed External Accessory protocol to ProjectZD8. Before the
   iPhone transport can be implemented and built, obtain from OBD Solutions:
   - the exact reverse-DNS External Accessory protocol string;
   - confirmation that this app and development team may communicate with MX+;
   - the supported stream framing or SDK contract;
   - connection, authentication, and reconnection requirements.
4. After those values are supplied, the required implementation is an iOS-only
   `ExternalAccessory` discovery and `EASession` transport, the exact
   `UISupportedExternalAccessoryProtocols` entry, Composition injection, and an
   opt-in iPhone hardware test. Until then, iPhone ProjectZD8 communication must
   remain explicitly unavailable.

Suggested manufacturer request:

> We are developing an iPhone OBD application for OBDLink MX+. Please provide
> the supported External Accessory protocol string, third-party app
> authorization requirements, and the EASession byte-stream or SDK
> specification needed to send documented STN/ELM commands. We will not infer
> or reverse engineer the protocol.

## Handoff record

Record each result independently:

- macOS build and focused unit tests;
- iOS build;
- macOS OS pairing;
- macOS adapter-only RFCOMM/ATI test;
- iPhone OS pairing;
- iPhone manufacturer protocol authorization;
- ProjectZD8 VIN observation;
- ProjectZD8 PID observation;
- UI and accessibility human review;
- long-session and reconnection behavior.

