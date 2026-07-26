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
cause for the first observed failure. Both iOS and macOS failure presentations
show this stable code without exposing the accessory identifier or response.

## iPhone arrival procedure and external stop condition

1. Power the MX+ using the approved source, press its physical Connect button,
   and pair `OBDLink MX+` in iPhone Settings. The MX+ uses Bluetooth Classic,
   so a CoreBluetooth BLE scan is not proof of MX+ availability.
2. The official OBDLink app may be used separately to confirm the adapter and
   iPhone can pair. Close it before ProjectZD8 testing. Its success is not
   ProjectZD8 evidence.

### Experimental BLE inspection

The current trial build may scan all BLE advertisements so the selected physical
unit can settle the transport question. User-facing results are filtered after
scanning so only known OBD names (`OBDLink`, `VEEPEAK`, `Vgate`, `IOS-Vlink`) or
the explicitly supported UART Service UUIDs are shown. This is diagnostic
evidence, not a claim that the retail MX+ supports BLE.

The iPhone trial follows the Bluetooth setup and connect-after-selection flow in
[`kkonteh97/SwiftOBD2`](https://github.com/kkonteh97/SwiftOBD2/tree/fe6def4e8599671dfc1b9597dbcdbc6a7c078b96):
`NSBluetoothAlwaysUsageDescription`, the `bluetooth-central` background mode, a
10-second CoreBluetooth scan, and explicit `FFE0`, `FFF0`, and `18F0` UART
profiles. ProjectZD8 keeps its typed Application/Data boundaries and does not
adopt SwiftOBD2's arbitrary-characteristic fallback.

1. In ProjectZD8 Settings, refresh the primary adapter list and select only the
   candidate whose displayed name and physical device state you can correlate.
2. Open its detail sheet and record the Peripheral UUID and advertised Service
   UUIDs locally. Do not publish the Peripheral UUID.
3. The trial transport connects only when discovered characteristics match one
   of these explicit UART profiles; it does not guess arbitrary writable
   characteristics:
   - experimental supplied profile: Service
     `B3491406-44E4-4D83-97C5-CE3190130000`, combined Notify/Write
     `B3491406-44E4-4D83-97C5-CE3190130001`;
   - FFF0 profile: Notify `FFF1`, Write `FFF2`;
   - FFE0 profile: combined Notify/Write `FFE1`;
   - 18F0 profile: Notify `2AF0`, Write `2AF1`.
4. Xcode device logs record discovered Service/Characteristic UUIDs and the
   selected profile under `IOSCoreBluetoothOBDTransport`. They do not record a
   Bluetooth address, VIN, or command response payload.
5. Stop after candidate inspection unless vehicle identification has been
   explicitly approved. Pressing HOME Connect can send adapter initialization,
   `ATI`, `0902`, and `ATDP`; it is not an adapter-only probe.
6. If the unit is absent from the BLE list or no explicit profile matches, keep
   the result as an observed trial failure. Do not add a guessed UUID or infer
   BLE support from iPhone Settings pairing alone.

### Experimental ExternalAccessory trial

The project owner explicitly authorized a device-list trial using `com.obdlink`
on 2026-07-26. This value is configured in `ProjectZD8/Info.plist` for that
trial, but it has not been verified against manufacturer documentation. Its
presence is not evidence of third-party authorization or a working stream
contract.

1. Before this experimental value can be treated as production-ready, obtain
   from OBD Solutions:
   - the exact reverse-DNS External Accessory protocol string;
   - confirmation that this app and development team may communicate with MX+;
   - the supported stream framing or SDK contract;
   - connection, authentication, and reconnection requirements.
2. The iOS-only `ExternalAccessory` discovery, `EASession` byte stream, and
   Composition injection read the experimental `com.obdlink` value from
   `UISupportedExternalAccessoryProtocols`. Do not add a product name, bundle
   identifier, BLE service UUID, or another inferred reverse-DNS string.
3. Rebuild and install on the approved iPhone. In Settings, refresh the
   Bluetooth adapter list. ProjectZD8 may show only accessories that iOS exposes
   to this app, whose `protocolStrings` intersect the Info.plist allowlist, and
   which are currently connected. System pairing alone does not satisfy these
   conditions.
4. For this trial, stop after confirming whether the exact accessory name is
   present in the ProjectZD8 list. Do not press HOME Connect as part of the
   device-list trial.
5. Add and run an opt-in iPhone adapter-only hardware test before approving VIN
   or PID acquisition. The first adapter test must stop after a documented `ATI`
   response; real-vehicle commands still require separate explicit approval.

The current ExternalAccessory transport schedules both `EASession` streams on
the Main RunLoop common mode before opening them and removes them after close.
This follows Apple's stream lifecycle requirement but does not establish that
`com.obdlink` carries an unframed ELM/STN byte stream.

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
- iPhone BLE advertisement and discovered Service/Characteristic UUIDs;
- matched experimental BLE UART profile, if any;
- iPhone manufacturer protocol authorization;
- ProjectZD8 VIN observation;
- ProjectZD8 PID observation;
- UI and accessibility human review;
- long-session and reconnection behavior.
