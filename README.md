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
Der Quellstand ist über `anvil_version` in `post_install.yml` auf Commit
`47270baa475181950939722372b333f09f7a749e` festgelegt (Version 0.6.4).
Rust, Wayland, Mesa mit EGL/GBM und Software-Rendering, libinput und libseat
mit systemd-logind sowie `x11-themes/xcursor-themes` werden vorher installiert. Der Build verwendet zwei Jobs,
um den Speicherbedarf in der VM zu begrenzen.

Wayland, Anvil und unser Terminal [rst](https://github.com/dme86/rst) werden
bei `make install` standardmäßig installiert. rst wird ebenfalls mit
`cargo build --release --locked` gebaut und als `/usr/local/bin/rst` installiert;
`rst_version` legt den Quellstand auf Commit
`adf6368514fef75ea482e86805c50437757db67b` fest.

Anvil bringt Leiste, Launcher und Fensterübersicht mit. rst ist das
Standardterminal. Fensterabstände sind standardmäßig deaktiviert:
`layout.gap = 0` und `layout.outer_gap = 0`. Die Konfiguration liegt unter `~/.config/anvil/config.toml`;
die Tastaturbelegung ist Deutsch. Bestehende Anvil-Einstellungen bleiben
bis auf die verwaltete Tastaturbelegung, das Standardterminal und die
Fensterabstände erhalten. Neovim und Wallpapers
werden weiterhin ausgecheckt; ein Wallpaper-Dienst wird nicht gestartet.

Nach dem Boot auf der lokalen Konsole anmelden:

```text
gentoo login: dan
Password: dan
```

Auf tty1 startet danach automatisch Anvil als Benutzer `dan` in einer
D-Bus-Session. Andere Konsolen und SSH bleiben normale Shells. Ein manueller
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
automatischen Display-Manager. Nach dem Login auf tty1 startet Anvil. Die serielle Konsole
wird dort bewusst abgeschaltet, damit nur ein Login-Prompt angezeigt wird.
`Ctrl`+`Alt`+`G` gibt einen gefangenen Mauszeiger frei. Die VM wird im Gast mit
`poweroff` sauber beendet.

UTM kann weiterhin als Runner verwendet werden. Die bisherige X11-Integration
über `spice-vdagent`, `xrandr` und `feh` gilt für diese native Wayland-Session
nicht. Gemeinsame Zwischenablage und automatische Anpassung an die Fenstergröße
sind damit nicht zugesichert. Die DRM-/EGL-Ausgabe muss auf dem jeweiligen
QEMU-/UTM-Grafikgerät praktisch geprüft werden; ein erfolgreicher Build und
SSH-Test allein bestätigen noch keinen funktionierenden Desktop.

## Vorhandenes Image in UTM verwenden

UTM 4.7.5 oder neuer wird empfohlen; ältere Versionen haben einen bekannten
SPICE-Fehler, durch den die dynamische Auflösung ausfallen kann. Die qcow2-Datei
ist keine fertige `.utm`-VM und wird deshalb nicht über „Öffnen“ geladen:

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
