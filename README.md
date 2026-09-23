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

## Schnellstart: vollständige DWM-VM neu bauen

Auf einem ARM64-Host entsteht eine ARM64-VM, auf einem x86_64-Host eine
x86_64-VM. Cross-Architektur-Installationen sind absichtlich nicht vorgesehen.

```sh
git clone https://github.com/dme86/gentoo-ansible.git
cd gentoo-ansible
make install-full
```

`make install-full` installiert zuerst die benötigte Ansible-Collection und
führt danach den gesamten unbeaufsichtigten Ablauf aus: aktuelles Gentoo-ISO
laden und prüfen, qcow2 erzeugen, Gentoo installieren, testweise von der Platte
booten sowie Xorg, DWM, `st`, `dwmblocks`, Fonts, Dotfiles und SPICE-Unterstützung
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

## Basisinstallation und Optionen

```sh
make install
```

Dieser kürzere Build erzeugt nur ein bootfähiges Gentoo-Basissystem. Für die in
diesem README beschriebene DWM-VM ist stattdessen `make install-full` vorgesehen.

Ohne gesetztes Passwort wird ein zufälliges Root-Passwort erzeugt und am Ende
einmal ausgegeben. Für ein festes Passwort:

```sh
GENTOO_ROOT_PASSWORD='ein-sicheres-passwort' make install
```

Eine vorhandene Zieldatei wird absichtlich nicht überschrieben. Für einen
kompletten Full-Neubau nach einem abgebrochenen Installationsversuch:

```sh
make install-full-force
```

Dabei wird nur das unvollständige qcow2-Image ersetzt; bereits geladene ISOs im
`.qemu/cache` werden weiterverwendet.

Nützliche Optionen:

```text
--disk PATH        anderer Ausgabepfad
--disk-size 64G    andere virtuelle Plattengröße
--memory 8192      RAM in MiB
--cpus 8           Anzahl virtueller CPUs
--ssh-port 2223    lokaler Port für die VM
--keep-running     VM nach erfolgreicher Prüfung weiterlaufen lassen
--post-install     zusätzlich das persönliche post_install.yml ausführen
```

`make install-full` entspricht einer Installation mit `--post-install`. Dieser
Schritt installiert den Benutzer `dan`, dessen Dotfiles sowie Desktop- und
CLI-Pakete aus der Projektkonfiguration. Dazu gehören Xorg sowie die persönlichen
Repositories für `dwm`, `dwmblocks`, `st`, Neovim und die Wallpapers. `dwm`,
`dwmblocks` und `st` werden
automatisch gebaut und nach `/usr/local/bin` installiert. Eine passende
`/home/dan/.xinitrc` setzt die X11-Tastatur auf Deutsch und startet anschließend
`dwm` in einer D-Bus-Session. Hack und die Nerd-Font-Symbole werden als getrennte
Gentoo-Pakete installiert und per Fontconfig zur von der DWM-Konfiguration
erwarteten Familie `Hack Nerd Font` zusammengesetzt. Ein kleiner RandR-Watcher
führt die von `feh` erzeugte `~/.fehbg` nach einer dynamischen Änderung der
UTM-Fenstergröße erneut aus, damit das Wallpaper passend skaliert statt gekachelt
wird.

Nach `install-full` genügt daher:

```text
gentoo login: dan
Password: dan
$ startx
```

In `dwm` öffnet `Alt`+`Shift`+`Enter` das mitinstallierte `st`; `Alt`+`P` startet
`dmenu`. Beendet wird `dwm` gemäß der persönlichen Konfiguration mit dessen
Quit-Tastenkombination. Ein Display-Manager wird bewusst nicht installiert.

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
automatischen Display-Manager. Nach einer Basisinstallation (`make install`) ist
nur die Textkonsole vorhanden; nach `make install-full` kann `dan` sich anmelden
und `startx` für den vorkonfigurierten DWM-Desktop ausführen. Die serielle Konsole
wird dort bewusst abgeschaltet, damit nur ein Login-Prompt angezeigt wird.
`Ctrl`+`Alt`+`G` gibt einen gefangenen Mauszeiger frei. Die VM wird im Gast mit
`poweroff` sauber beendet.

Für die spätere Desktop-Nutzung ist UTM der vorgesehene komfortable Runner.
`install-full` installiert dafür `app-emulation/spice-vdagent`. Wird das qcow2-
Image in einer UTM-QEMU-VM als VirtIO-Laufwerk verwendet und in UTM
„Clipboard Sharing“ aktiviert, stehen nach Installation eines X11-/Wayland-
Desktops gemeinsame Zwischenablage und dynamische Bildschirmauflösung bereit.
Das reine QEMU-Cocoa-Fenster unterstützt diese Desktop-Integration nicht.

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
9. Unter „Freigaben“ das Clipboard-Sharing aktivieren.

UTM kopiert das nicht wechselbare Image in das `.utm`-Paket. Danach sind das
Original unter `.qemu` und die von UTM verwendete Platte zwei unabhängige
Dateien.

Nach dem Boot:

```text
gentoo login: dan
Password: dan
$ startx
```

Die Auflösung folgt dem UTM-Fenster. Der installierte Wallpaper-Watcher rendert
das aktuelle `feh`-Hintergrundbild bei jeder Größenänderung neu. Falls die
Auflösung ausnahmsweise nicht aktualisiert wird:

```sh
xrandr --output Virtual-1 --auto
```

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

Der Installer akzeptiert als Zielgerät absichtlich nur `/dev/vda`; dadurch kann
das Playbook nicht versehentlich eine beliebige Host-Festplatte überschreiben.
