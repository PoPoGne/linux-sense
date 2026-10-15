<p align="center"><img src="logo/out/linux-sense-256.png" width="128" alt="Linux Sense"></p>

# Linux Sense

Pannello di controllo per portatili **Acer Nitro** su Linux, alternativo a NitroSense.
È nato su un Acer Nitro 14 (AN14-41) con Fedora 44 KDE e kernel 7.2.

- **Profili termici**: Eco, Silenzioso, Bilanciato, Prestazioni e Turbo, sincronizzati col tasto fisico dei profili
- **Ventole**: automatiche, al massimo o manuali, con i giri in tempo reale
- **Tastiera RGB a 4 zone**: colori per zona ed effetti, con anteprima animata
- **Batteria**: limite di carica all'80%, calibrazione, ricarica USB a portatile spento, salute e autonomia
- **Profilo automatico**: un profilo per l'alimentatore e uno per la batteria
- **Tasto N** della tastiera per aprire l'app

## Struttura

| Cartella | Contenuto |
|---|---|
| `app/` | Interfaccia (Python + PySide6/QML), font e icone |
| `daemon/` | Servizio root `linux-sense.service`: socket `/run/linux-sense.sock`, JSON a righe |
| `driver/` | Driver `linuwu_sense` 25.701 per DKMS con le patch locali (`linux-sense.patch`) |
| `system/` | Regola hwdb per il tasto N e unit per scaricare il driver allo spegnimento |
| `scripts/` | Registrazione della scorciatoia KDE |
| `logo/` | Logo generato con `vectorcraft-cli` (`build_logo.py`) e file esportati |

## Installazione

```bash
sudo ./install.sh
```

Lo script:
- compila e installa il driver con DKMS (si ricompila da solo a ogni kernel nuovo) e mette `acer_wmi` in blacklist;
- installa servizio, app, icone e voce di menu in `/opt/linux-sense`;
- rimappa il tasto N e lo assegna all'apertura dell'app in KDE.

Si può rilanciare per aggiornare dopo una modifica.

Dipendenze: `python3-pyside6`, `kernel-devel`, `dkms`, `gcc`, `make`.

## Note tecniche

- Il profilo si legge e si scrive sul gestore platform-profile `acer-wmi`. Il servizio lo propaga a `amd-pmf`.
  L'interfaccia legacy `/sys/firmware/acpi/platform_profile` restituisce `custom` quando i due gestori divergono.
- A batteria il firmware accetta solo Eco e Bilanciato.
  In Eco e Silenzioso le ventole sono sempre gestite dal firmware.
- Il tasto N invia lo scancode `0xf5`, che di default diventa il codice 425 e non è usabile da KDE.
  Viene rimappato su `prog1` (XF86Launch1).

### Patch al driver

Il driver viene da [Linuwu-Sense](https://github.com/0x7375646F/Linuwu-Sense), nella versione inclusa in [DAMX](https://github.com/PXDiv/Div-Acer-Manager-Max).
Le modifiche sono due:
- `strncpy` sostituito da `memcpy`, perché la funzione è stata rimossa dal kernel 7.x;
- aggiunta del modello `Nitro AN14-41` alla tabella DMI, con le stesse impostazioni dell'AN16-41.

## Crediti

Driver Linuwu-Sense (GPL-2.0), progetto di partenza DAMX (GPL-3.0).
Icone [Lucide](https://lucide.dev) (ISC), caratteri Rajdhani e Inter (SIL OFL).
