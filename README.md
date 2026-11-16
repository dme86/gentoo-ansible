# Gentoo-on-QEMU mit Ansible

Das Projekt erzeugt aus dem jeweils aktuellen offiziellen Gentoo-Minimal-ISO
eine bootfähige QEMU-Festplatte. Der Ablauf ist vollständig unbeaufsichtigt:

1. Host-Architektur erkennen (`x86_64` → `amd64`, `arm64`/`aarch64` → `arm64`)
2. aktuelles ISO anhand des Gentoo-Manifests laden und per SHA-256 prüfen
3. eine neue qcow2-Festplatte erzeugen und das ISO mit temporärem SSH booten
4. `install.yml` gegen das Live-System ausführen
5. GPT, EFI, Btrfs-Subvolumes und ein systemd-Stage3 installieren
6. Kernel, Initramfs, systemd-boot, Netzwerk und SSH konfigurieren
7. von der Festplatte per UEFI booten und die Installation über SSH verifizieren

Das Ergebnis liegt standardmäßig unter `.qemu/gentoo.qcow2`. Downloads werden
unter `.qemu/cache` wiederverwendet.

## Schnellstart: vollständige Anvil-VM neu bauen

Auf einem ARM64-Host entsteht eine ARM64-VM, auf einem x86_64-Host eine
x86_64-VM. Cross-Architektur-Installationen sind absichtlich nicht vorgesehen.

```sh
git clone https://github.com/dme86/gentoo-ansible.git
cd gentoo-ansible
make install
```

`make install` installiert zuerst die benötigte Ansible-Collection und
führt danach den gesamten unbeaufsichtigten Ablauf aus: aktuelles Gentoo-ISO
laden und prüfen, qcow2 erzeugen, Gentoo installieren, testweise von der Platte
booten sowie Wayland, Anvil, rst, Fonts und die persönlichen Repositories
einrichten. Je nach Host und Verfügbarkeit von Binärpaketen dauert das deutlich
länger als eine reine Basisinstallation.

Nach erfolgreichem Abschluss liegt das portable Image hier:

```text
.qemu/gentoo.qcow2
```

## Voraussetzungen

- QEMU inklusive `qemu-img` und edk2/OVMF
- Ansible
- `curl`, `bsdtar`, OpenSSH, `sshpass` und `openssl`
- Git und GNU Make
- mindestens etwa 20 GiB freier Host-Speicher für den Full-Build samt
  Download-Cache; die virtuelle Platte ist 32 GiB groß und wächst dynamisch

macOS mit Homebrew:

```sh
brew install qemu ansible sshpass
```

Falls Homebrew noch nicht verwendet wurde, müssen einmalig Apples Command Line
Tools installiert sein:

```sh
xcode-select --install
```

Auf Debian/Ubuntu heißen die benötigten Pakete je nach Host-Architektur ungefähr:

```sh
sudo apt install ansible curl git libarchive-tools make openssh-client openssl \
  qemu-system-arm qemu-system-x86 qemu-utils ovmf qemu-efi-aarch64 sshpass
```

Nicht jede Distribution trennt QEMU und die UEFI-Firmware in dieselben Pakete.
Der Installer nennt fehlende Programme beziehungsweise Firmware beim Start.

Unter Linux wird KVM automatisch genutzt, wenn `/dev/kvm` zugänglich ist.
Ansonsten fällt der Installer auf TCG zurück. Unter macOS wird HVF verwendet.

## Installation und Optionen

Ohne gesetztes Passwort wird ein zufälliges Root-Passwort erzeugt und am Ende
einmal ausgegeben. Für ein festes Passwort:

```sh
GENTOO_ROOT_PASSWORD='ein-sicheres-passwort' make install
```

Eine vorhandene Zieldatei wird absichtlich nicht überschrieben. Für einen
kompletten Full-Neubau nach einem abgebrochenen Installationsversuch:

```sh
make install ARGS="--force"
```

Dabei wird das vorhandene qcow2-Image ersetzt; bereits geladene ISOs im
`.qemu/cache` werden weiterverwendet.

Zusätzliche Installer-Optionen werden über `ARGS` übergeben, zum Beispiel:

```sh
make install ARGS="--memory 8192 --cpus 8"
```

Nützliche Optionen:

```text
--disk PATH        anderer Ausgabepfad
--disk-size 64G    andere virtuelle Plattengröße
--memory 8192      RAM in MiB
--cpus 8           Anzahl virtueller CPUs
--ssh-port 2223    lokaler Port für die VM
--keep-running     VM nach erfolgreicher Prüfung weiterlaufen lassen
--force            vorhandenes Ziel-Image ersetzen
```

Die Desktop-Konfiguration baut [Anvil](https://github.com/dme86/anvil) und
`anvilctl` direkt in der Gentoo-VM mit `cargo build --release --locked`.
Der Quellstand ist über `anvil_version` in `post_install.yml` auf einen
reproduzierbaren Commit festgelegt. Die VM-Zwischenablage benötigt Anvils native
Wayland-Data-Control-Unterstützung; XWayland ist dafür nicht erforderlich.

Die Nachinstallation richtet außerdem Neofetch so ein, dass es eine Anvil-Sitzung
korrekt als `WM: Anvil` erkennt. Vorhandene Einstellungen bleiben erhalten; die
ursprüngliche Konfiguration wird einmal gesichert. Der Hook greift nur innerhalb
einer Anvil-Wayland-Sitzung, damit `swaybg` nicht mehr als Sway fehlinterpretiert wird.
Rust, Wayland, Mesa mit EGL/GBM und Software-Rendering, libinput und libseat
mit systemd-logind sowie `x11-themes/xcursor-themes` werden vorher installiert. Der Build verwendet zwei Jobs,
um den Speicherbedarf in der VM zu begrenzen.

Wayland, Anvil und unser Terminal [rst](https://github.com/dme86/rst) werden
bei `make install` standardmäßig installiert. rst wird ebenfalls mit
`cargo build --release --locked` gebaut und als `/usr/local/bin/rst` installiert;
`rst_version` legt den Quellstand auf Commit
`0e80ddd948cf0026691d8d7b957a4f0755eb64e0` fest.

In erkannten QEMU-/KVM-Gästen installiert die Nachinstallation außerdem
[Paprika v0.2.1](https://github.com/thelicato/paprika-vdagent/tree/c65de8829ad126997f868c3cab9c00d6dab90023)
am festgelegten Commit `c65de8829ad126997f868c3cab9c00d6dab90023` mit
`cargo build --release --locked` und `gui-apps/wl-clipboard` zur Diagnose.
Auf nativer Hardware bleibt diese Integration standardmäßig deaktiviert.

Für QEMUs nativen Clipboard-Kanal kommt zusätzlich der eng begrenzte, überprüfte
Patch [`patches/paprika-native-qemu.patch`](patches/paprika-native-qemu.patch)
zum Einsatz. Er lässt QEMU den Capability-Handshake beginnen und sendet die
Antwort vor der ersten Clipboard-Ankündigung. Der gepinnte Upstream-Checkout
bleibt unverändert: Ansible wendet den Patch in einem separaten Git-Worktree
unter `~/.cache/anvil-vm` an, dessen Name Quellcommit und Patch-Hash enthält.
Ein privater Cargo-Cache bleibt vom normalen Upstream-Build getrennt; Cargo
prüft bei jeder Nachinstallation den tatsächlich gewählten Quellstand.
Der Patch korrigiert außerdem die Reihenfolge wiederholter Clipboard-Wechsel
zwischen Host und Gast. Details und Regressionstests stehen in
[`patches/README.md`](patches/README.md).
`vm_clipboard_native_qemu=true` aktiviert diesen Handshake über
`PAPRIKA_VDAGENT_QEMU_NATIVE=1` im Benutzerdienst. Mit `false` bleibt die
ursprüngliche, vom Gast begonnene SPICE-Aushandlung erhalten.

Anvil bringt Leiste, Launcher und Fensterübersicht mit. rst ist das
Standardterminal. Fensterabstände sind standardmäßig deaktiviert:
`layout.gap = 0` und `layout.outer_gap = 0`. Die Konfiguration liegt unter `~/.config/anvil/config.toml`;
die Tastaturbelegung ist Deutsch. Bestehende Anvil-Einstellungen bleiben
bis auf die verwaltete Tastaturbelegung, das Standardterminal und die
Fensterabstände erhalten. Neovim und Wallpapers
werden weiterhin ausgecheckt. Anvil startet pro Sitzung `swaybg` mit einem
zufällig gewählten Wallpaper aus `~/.wallpapers/files`.

Nach dem Boot bei tuigreet mit Benutzer `dan` und Passwort `dan` anmelden:

```text
gentoo login: dan
Password: dan
```

Auf tty1 zeigt greetd den minimalen tuigreet-Anmeldebildschirm. Nach der
Anmeldung startet Anvil als Benutzer `dan` in einer D-Bus-Session. Andere Konsolen und SSH bleiben normale Shells. Ein manueller
Start aus einer freien lokalen Konsole ist mit `start-anvil` möglich.
Es gibt keinen automatischen Login. `Super+Return` öffnet rst,
`Super+p` den Launcher und `Super+Tab` die Fensterübersicht.
XWayland ist in diesem Build nicht aktiviert.

Unabhängig davon wird bei jeder Basisinstallation der Konsolenbenutzer `dan`
angelegt. Sein initiales Passwort ist `dan`; er darf mit diesem Passwort `sudo`
verwenden. Das ist nur für die lokale QEMU-Testmaschine gedacht und sollte für
andere Einsatzzwecke sofort geändert werden. Die Textkonsole verwendet eine
deutsche Tastaturbelegung, während Systemsprache und Meldungen Englisch bleiben.

## Start mit Vanilla-QEMU

```sh
make run-graphical
```

Der Starter öffnet eine QEMU-Fensterkonsole mit Tastatur und Maus, aber keinen
zusätzlichen grafischen Display-Manager. greetd mit tuigreet übernimmt die
Anmeldung auf tty1 und startet Anvil. Die serielle Konsole
wird dort bewusst abgeschaltet, damit nur ein Login-Prompt angezeigt wird.
`Ctrl`+`Alt`+`G` gibt einen gefangenen Mauszeiger frei. Die VM wird im Gast mit
`poweroff` sauber beendet.

Unter macOS verwendet der Starter `-display cocoa,zoom-to-fit=on`. Zoom To Fit
ermöglicht Größenänderungen des nativen QEMU-Fensters. QEMU meldet die neue
Displaygröße über VirtIO als bevorzugten DRM-Modus; Anvil folgt diesem Modus,
solange für den Ausgang kein fester `mode` in `[[outputs]]` konfiguriert ist.
`anvilctl output list` zeigt den aktuellen und bevorzugten Modus. Cocoa bindet
das Fenster weiterhin an das aktuelle Seitenverhältnis; Breite und Höhe lassen
sich damit nicht beliebig unabhängig voneinander ziehen. `QEMU_DISPLAY` kann
die Display-Einstellung ausdrücklich überschreiben.

Der Starter richtet standardmäßig den QEMU-Clipboard-Kanal `qemu-vdagent` mit
dem VirtIO-Port `com.redhat.spice.0` ein. Paprika verbindet ihn innerhalb der
angemeldeten Anvil-Sitzung mit der nativen Wayland-Zwischenablage über Data
Control. Es läuft als Benutzer, ohne `spice-vdagentd` und ohne XWayland.
Die Port-Regel erlaubt nur root und der Gruppe des Desktop-Benutzers Zugriff
(`0660`). Vorhandene SPICE-Standarddienste werden maskiert; manuell laufende
`spice-vdagent`-Prozesse müssen ebenfalls beendet werden.

Diese Host-Brücke überträgt **UTF-8-Text**. Clipboard-Bilder werden nicht
unterstützt; eingehende Dateitransfers sind für diese Integration deaktiviert.
In rst **innerhalb der VM** kopiert `Ctrl`+`Shift`+`C` die Auswahl und
`Ctrl`+`Shift`+`V` fügt Text ein. Die macOS-Tastenkürzel des Host-Terminals
ersetzen diese Gast-Tastenkürzel nicht.

`make run-graphical` startet nur das vorhandene Image mit den Host-Optionen.
Die Gast-Pakete, Berechtigungen und Anvil-Autostart-Hilfe richtet dagegen
`make post-install` über SSH in der bereits laufenden VM ein. Nach einer
Aktualisierung von Anvil ist eine neue Anmeldung nötig, damit der neue
Compositor samt Clipboard-Hilfe läuft. Eine bestehende VM daher zuerst starten,
in einem zweiten Host-Terminal nachinstallieren und anschließend im Gast
abmelden und neu anmelden.

Die beiden Seiten lassen sich getrennt deaktivieren:

```sh
# Host: nächsten QEMU-Start ohne Clipboard-Kanal ausführen.
VM_CLIPBOARD=0 make run-graphical

# Gast: laufende Brücke stoppen und ihren Anvil-Autostart entfernen.
make post-install ARGS="-e vm_clipboard_enabled=false"
```

`vm_clipboard_enabled=true` kann die Gast-Integration auch für andere
SPICE-Runner ausdrücklich aktivieren. Für einen regulären SPICE-Server,
beispielsweise in UTM, muss zusätzlich der native QEMU-Handshake deaktiviert
werden:

```sh
make post-install ARGS="-e vm_clipboard_enabled=true -e vm_clipboard_native_qemu=false"
```

Die VM muss dabei über das vorhandene Ansible-Inventory erreichbar sein.
`vm_clipboard_enabled=false` deinstalliert bereits vorhandene Pakete nicht.
Fehlt dem Host-QEMU `qemu-vdagent`, erklärt der
Starter den Fehler vor dem Boot; `VM_CLIPBOARD=0` erlaubt den Start ohne Brücke.

Zur Diagnose diese Befehle **in einem Terminal der Anvil-Gastsitzung** ausführen:

```sh
paprika-vdagent --backend wayland doctor
anvilctl output list
DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/bus" \
  systemctl --user status paprika-vdagent.service
journalctl --user -u paprika-vdagent.service -b --no-pager
```

Der explizite Buspfad erreicht den systemd-Benutzermanager auch innerhalb der
privaten D-Bus-Sitzung von `start-anvil`. Die Hilfe
`/usr/local/bin/anvil-vm-clipboard` übernimmt beim Login ausschließlich die
aktuellen Display-Einstellungen in ein privates Service-Drop-in und startet den
Benutzerdienst neu. Bei Transportfehlern versucht der Dienst nach zwei Sekunden
einen Neustart. Ohne Port oder erreichbaren Compositor beendet sich die Hilfe
still; nach einer späteren Port-/Berechtigungsänderung kann sie innerhalb der
Gastsitzung erneut aufgerufen werden. Ein Benutzerdienst folgt jeweils der
zuletzt gestarteten grafischen Sitzung dieses Benutzers.

Die Launcher- und Helfer-Regressionsprüfungen benötigen keine laufende VM und
lesen keine Zwischenablage:

```sh
make test-vm-integration
```

Sie prüfen Startargumente und Sitzungsverwaltung. Ein tatsächlicher
Fenstergrößenwechsel unter macOS wurde zusätzlich geprüft: Der bevorzugte und
aktuelle Gast-Modus wechselte von `512x320` auf `768x480`; die rst-PTY passte sich
von 50 Spalten und 14 Zeilen auf 75 Spalten und 22 Zeilen an. Textübertragung
wurde bytegenau in beiden Richtungen geprüft: Unicode und mehrere Zeilen
(66/91 Bytes) sowie größere Texte (159747/159770 Bytes). Nach absichtlichem
Beenden des Dienstes verband er sich automatisch erneut; dieselben Tests
bestanden danach wieder. Das bestätigt den Transport und die Wayland-Auswahl;
weitere Testdetails und Grenzen stehen in
[`docs/vm-integration-testing.md`](docs/vm-integration-testing.md).

## Vorhandenes Image in UTM verwenden

UTM bleibt ein optionaler Runner und ist für den nativen QEMU-Start oben nicht
erforderlich. Die UTM-Variante wird mit diesem Integrationsstand nicht praktisch
mitgeprüft. Dort muss der Runner einen passenden SPICE-Kanal bereitstellen;
die QEMU-Startoptionen aus `qemu-graphical.sh` werden von UTM nicht übernommen.
Die Gast-Einstellung `vm_clipboard_native_qemu=false` erhält die reguläre
SPICE-Aushandlung, wie oben gezeigt.
Die qcow2-Datei ist keine fertige `.utm`-VM und wird deshalb nicht über „Öffnen“ geladen:

1. In UTM `+` → „Neue virtuelle Maschine“ → „Emulieren“ → „Andere“ wählen.
2. Dieselbe Architektur wie der Build-Host auswählen (`ARM64/aarch64` oder
   `x86_64`).
3. VM zunächst ohne Boot-ISO erstellen und speichern.
4. In den VM-Einstellungen das automatisch erzeugte leere Laufwerk entfernen.
5. Unter „Laufwerke“ → „Neu…“ ausdrücklich „Laufwerk importieren“ wählen und
   `.qemu/gentoo.qcow2` auswählen.
6. Image-Typ „Disk Image“, Schnittstelle „VirtIO“, nicht wechselbar,
   nicht schreibgeschützt einstellen.
7. Unter QEMU „UEFI Boot“ und „Use Hypervisor“ aktivieren.
8. Als Display `virtio-gpu-pci` ohne `-gl` auswählen und „Auto Resolution“
   aktivieren. `virtio-ramfb` führt bei diesem Image nach systemd-boot zu einem
   inaktiven Display.
9. Die VM starten und als `dan` anmelden; auf tty1 startet Anvil automatisch.

UTM kopiert das nicht wechselbare Image in das `.utm`-Paket. Danach sind das
Original unter `.qemu` und die von UTM verwendete Platte zwei unabhängige
Dateien.

Nach dem Boot:

```text
gentoo login: dan
Password: dan
```

Anvil-Ausgänge lassen sich innerhalb der laufenden Sitzung mit
`anvilctl output list` anzeigen und über `[[outputs]]` in
`~/.config/anvil/config.toml` konfigurieren.

Falls die Firmware nicht automatisch gefunden wird, kann sie explizit gesetzt
werden:

```sh
QEMU_EFI=/pfad/zu/edk2-aarch64-code.fd make install
```

## Dateien

- `scripts/qemu-install.sh` orchestriert Download, QEMU, Ansible und Testboot.
- `scripts/qemu-graphical.sh` startet ein vorhandenes Image mit Fensterkonsole.
- `scripts/anvil-vm-clipboard.py` startet die Text-Clipboard-Brücke in der Anvil-Gastsitzung.
- `scripts/test-qemu-graphical.py` und `scripts/test-vm-clipboard.py` prüfen die VM-Integration ohne VM-Start.
- `install.yml` installiert das Basissystem aus dem laufenden Minimal-ISO.
- `post_install.yml` enthält die optionale persönliche Nachkonfiguration.
- `.qemu/live-console.log` und `.qemu/disk-console.log` helfen bei Bootfehlern.
- `.qemu/diagnostics/` enthält bei fehlgeschlagenen Basispaket-Builds die
  gesicherten Portage-Logs. Portage protokolliert zusätzlich unter
  `/var/log/portage` im Gast; vor dem Beenden wird das Dateisystem synchronisiert.

Der Installer akzeptiert als Zielgerät absichtlich nur `/dev/vda`; dadurch kann
das Playbook nicht versehentlich eine beliebige Host-Festplatte überschreiben.

## Nachinstallation nach einem Abbruch fortsetzen

Wenn die Basisinstallation abgeschlossen ist und `post_install.yml` abbricht,
bleibt das installierte System in `.qemu/gentoo.qcow2` erhalten. Nicht erneut
mit `--force` installieren: Das würde das vorhandene Image ersetzen.

Im Repository zuerst `git pull --ff-only` ausführen. Die vorhandene VM starten:

```sh
make run-graphical
```

Nach dem Boot in einem zweiten Terminal im selben Repository die
Nachinstallation erneut ausführen:

```sh
make post-install
```

Der Befehl verwendet das beim Installieren erzeugte `.qemu/inventory.ini`
und den zugehörigen SSH-Schlüssel. Die VM muss über den dort eingetragenen
SSH-Port erreichbar sein (standardmäßig 2222; bei abweichendem Port mit
`SSH_PORT=2223 make run-graphical` starten). Falls die VM bereits läuft,
entfällt `make run-graphical`.

Der rst-Quellstand enthält eine eingecheckte `Cargo.lock`, damit der Build
mit `--locked` auch auf einer frischen Installation funktioniert.

Lokale Änderungen im verwalteten rst-Build-Verzeichnis werden vor einem Update
mit `git stash push --include-untracked` gesichert. Sie lassen sich in der VM
mit `git -C ~/.local/src/rst stash list` anzeigen und bei Bedarf gezielt
wiederherstellen. Die Sicherung wird nicht automatisch auf den neuen
Quellstand angewendet. Ignorierte Build-Dateien bleiben bestehen.

Bei beschädigten Git-Objekten oder Referenzen sichert der Installer das gesamte
rst-Verzeichnis unter `~/.local/src/rst-recovery-*/checkout` und klont frisch.
Auch die bisherigen Git-Stashes bleiben dadurch in der Sicherung erhalten.

Der Sitzungsstarter verwendet standardmäßig das Cursor-Theme `whiteglass`.
Ein vorhandenes `XCURSOR_THEME` bleibt erhalten. Das Theme-Paket stellt den
für den Anvil-Start benötigten Mauszeiger `left_ptr` bereit.
Der Starter ergänzt außerdem Gentoos Cursor-Suchpfad `/usr/share/cursors/xorg-x11`.

## Minimaler Greeter: greetd und tuigreet

`make install` richtet standardmäßig greetd mit tuigreet auf tty1 ein.
Es gibt keinen automatischen Login. Nach der Anmeldung startet `start-anvil`;
beim Beenden von Anvil erscheint wieder der Greeter. Andere Konsolen und SSH
bleiben verfügbar. Der frühere Anvil-Autostart in `.bash_profile` wird entfernt.

greetd wird über Portage installiert (auf ARM64 mit passender Keyword-Freigabe).
tuigreet wird aus https://github.com/tuigreet/tuigreet am festgelegten Commit
`4e3a0054a51ab35242d63d5b47e503d314808c52` mit `--locked` gebaut.
Die Konfiguration liegt unter `/etc/greetd/config.toml`, der Benutzercache unter
`/var/cache/tuigreet`. tty1-getty wird maskiert, damit beide Anmeldungen nicht
miteinander konkurrieren. Änderungen aktivieren den Dienst für den nächsten
Boot, ohne die aktuelle Sitzung zu beenden.

Für eine bestehende VM: `make post-install` ausführen und anschließend in der VM
`sudo reboot`. Auf dem Host ersetzt dieser Ablauf das vorhandene Image nicht.

## Zufälliges Wallpaper pro Desktop-Sitzung

Anvil startet über `general.startup` den Helfer `/usr/local/bin/anvil-wallpaper`.
Er wählt bei jeder neuen Sitzung zufällig eine PNG- oder JPEG-Datei aus
`~/.wallpapers/files` und ersetzt sich durch `swaybg --mode fill`. Das Bild
füllt den Bildschirm mit beibehaltenem Seitenverhältnis; Ränder können dabei
beschnitten werden. Alle Ausgänge verwenden dasselbe Bild. greetd bleibt
für die Anmeldung zuständig; der Greeter erhält kein Wallpaper.

Das Wallpaper-Repository https://github.com/dme86/.wallpapers wird bereits
bei der Installation geklont. `make post-install` installiert `swaybg` und
richtet den Startup-Eintrag ein, ohne andere Startup-Kommandos zu ersetzen.
Neue Bilder werden beim nächsten Sitzungsstart berücksichtigt. Mit `git -C ~/.wallpapers pull --ff-only` in der VM lässt sich die
Bildersammlung aktualisieren.
Fehlen Bilder, beendet sich der Helfer ohne die Anmeldung zu blockieren.

## Speicherverbrauch in ARM64-QEMU-Gästen

Die Anvil-Oberfläche lädt Schriftkonturen mit FreeType erst bei Bedarf und
behält nur begrenzte Glyphen-Caches. Nerd-Font-Symbole und Fontconfig-Fallbacks
bleiben verfügbar; eine kleinere Schrift ist dafür nicht nötig.

In erkannten ARM64-QEMU/KVM-Gästen setzt der Sitzungsstarter standardmäßig
`GLIBC_TUNABLES=glibc.malloc.hugetlb=0`. Das vermeidet die in dieser VM gemessene
Speicherverschwendung durch glibcs automatische Heap-Hugepages. Native Hardware
behält ihre Standardeinstellung. Ein bereits gesetztes `GLIBC_TUNABLES` bleibt
erhalten; mit `-e anvil_glibc_tunables=` lässt sich die Vorgabe deaktivieren.
Die Einstellung wird auch an Programme vererbt, die aus der Sitzung starten.

Im vergleichbaren Test sank Anvil von etwa 198 MiB auf 151 MiB durch die
Schriftänderung und auf 103 MiB mit der VM-Einstellung. Ein direktes DRM-Szenario
mit einem Testterminal lag bei 101 MiB und 54–58 Bildern/s ohne Renderfehler.
Die Werte hängen von Treiber, Ausgängen, Fenstern und Arbeitslast ab.
