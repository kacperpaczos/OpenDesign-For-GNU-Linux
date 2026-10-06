# Pakiety społecznościowe Linuksa — procedura przebudowy

Ten dokument opisuje, jak dla każdego stabilnego wydania upstreamu zbudować pakiety `.deb`, `.rpm` i `.flatpak` dla OpenDesign. Pakiety powstają z tagów upstreamu (`nexu-io/open-design`) z nałożoną naszą serią łatek przez cherry-pick.

**Serie łatek:** commity po tagu bazowym (zapisanym w `packaging/linux/SERIES-BASE`) aż do gałęzi `linux-packages-0.24.1` — domyślnej gałęzi forka `kacperpaczos/open-design`. Obecnie baza to `open-design-v0.24.1`.

## Jak działa automat (CI)

Workflow `.github/workflows/linux-packages.yml`:

1. codziennie o 03:41 UTC (i na żądanie) wyznacza najnowszy tag upstreamu pasujący do `open-design-v*`;
2. jeśli na forku istnieje już wydanie o nazwie `<tag>-linux`, nic nie robi;
3. w przeciwnym razie zakłada gałąź `linux-build` na tagu upstreamu i nanosi naszą serię przez cherry-pick z zakresu `"$(grep -v '^#' packaging/linux/SERIES-BASE | sed -n '1p')"..linux-packages-0.24.1`. **Konflikt oznacza, że upstream przepisał łatany obszar** — workflow przerywa pracę z czytelnym komunikatem i trzeba przeciąć serię ręcznie (punkt (b) niżej);
4. buduje `.deb`, potem `.rpm` (sekwencyjnie, jeden runner); Flatpak buduje osobno, jako best-effort — jego porażka nie blokuje deb/rpm ani wydania;
5. publikuje wydanie `<tag>-linux` ze wszystkimi artefaktami i notką (co nałożono, jak instalować, znane zastrzeżenia).

## (a) Przebudowa przez CI — sposób zalecany

```bash
# automatycznie: najnowszy tag upstreamu
gh workflow run linux-packages.yml -R kacperpaczos/open-design

# albo konkretny tag
gh workflow run linux-packages.yml -R kacperpaczos/open-design -f tag=open-design-v0.25.0
```

Postęp podglądasz przez `gh run watch` albo zakładkę Actions na forku. Efekt: wydanie `open-design-vX.Y.Z-linux` na `kacperpaczos/open-design`.

## (b) Przebudowa lokalna — gdy CI nie wystarcza (np. konflikt cherry-pick)

### 1. Pobierz nowy tag upstreamu

```bash
git remote add upstream https://github.com/nexu-io/open-design.git  # jeśli jeszcze go nie ma
git fetch upstream "refs/tags/open-design-v0.25.0:refs/tags/open-design-v0.25.0"
```

### 2. Zapisz bazę serii i załóż gałąź na tagu

Bazę serii przeczytaj **przed** checkoutem: plik `packaging/linux/SERIES-BASE` ma w pierwszej linii komentarz (trzeba go odfiltrować, bo inaczej git dostanie zły zakres) i istnieje tylko na gałęzi serii — checkout tagu upstreamu usuwa go z drzewa roboczego.

```bash
BASE="$(grep -v '^#' packaging/linux/SERIES-BASE | sed -n '1p')"

git checkout -B linux-packages-0.25.0 open-design-v0.25.0
```

### 3. Nałóż serię łatek

```bash
git cherry-pick "$BASE"..linux-packages-0.24.1
```

Konflikty rozwiązuj zgodnie z **intencją łatki** (co miała osiągnąć), a nie mechanicznie. Jeśli upstream usunął lub przepisał łatany obszar, zastanów się najpierw, czy łatka jest wciąż potrzebna — może problem naprawiono po swojej stronie.

### 4. Aktualizacja `packaging/linux/SERIES-BASE`

Zaktualizuj plik **tylko wtedy, gdy przecinasz serię na nową bazę** (czyli nowa gałąź serii staje się kanoniczna): wpisz nowy tag bazowy, np. `open-design-v0.25.0`, i popraw komentarz w pierwszej linii. Przy zwykłej przebudowie tego samego tagu upstreamu — nie ruszaj pliku.

### 5. Budowa

```bash
pnpm install   # postinstall buduje wszystko

pnpm tools-pack linux build --to deb --portable
mkdir -p ../linux-out && find .tmp -name '*.deb' -exec cp {} ../linux-out/ \;

pnpm tools-pack linux build --to rpm --portable
find .tmp -name '*.rpm' -exec cp {} ../linux-out/ \;
```

Flaga `--portable` jest w budowach wydawniczych obowiązkowa: bez niej `open-design-config.json` w pakiecie zawiera `namespaceBaseRoot` — ścieżkę runtime z maszyny budującej — i aplikacja na każdej innej maszynie rzuca `PackagedPathAccessError` przy starcie.

**Uwaga — sprzątanie:** electron-builder czyści swój katalog wyjściowy przy **każdym** uruchomieniu (budowa deb usuwa artefakty po poprzedniej budowie). Dlatego każdy artefakt odkładaj na bok **przed następną budową** — katalog `../linux-out` leży poza repozytorium, więc sprzątanie go nie sięga.

Flatpak (best-effort):

```bash
pnpm tools-pack linux build --to dir --portable
# --user: środowiska zainstalowaliśmy --user (domyślnie flatpak-builder patrzy
# w instalacje systemowe i ich nie widzi); --repo: build-bundle czyta repozytorium
# ostree, nie katalog roboczy builddir.
flatpak-builder --user --force-clean --jobs=1 --repo=repo builddir packaging/flatpak/io.open-design.desktop.json
flatpak build-bundle repo open-design.flatpak io.opendesign.desktop
cp -v open-design.flatpak ../linux-out/
```

Wymaga: `flatpak` + `flatpak-builder`, zdalnego repozytorium flathub (`flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo`) oraz trójki środowisk 26.08: `org.freedesktop.Platform//26.08`, `org.freedesktop.Sdk//26.08`, `org.electronjs.Electron2.BaseApp//26.08`.

**Dyscyplina pamięci:** jedna budowa naraz; `flatpak-builder` wyłącznie z `--jobs=1`.

Sumy kontrolne (do publikacji razem z artefaktami):

```bash
cd ../linux-out && sha256sum *.deb *.rpm *.flatpak > sha256sums.txt
# weryfikacja po pobraniu:
sha256sum -c sha256sums.txt
```

### 6. Kontrola wersji

Numer wersji w pakiecie bierze się z zapakowanego `package.json` (nie z korzennego) i powinien odpowiadać tagowi upstreamu:

```bash
dpkg-deb -f ../linux-out/*.deb Version
rpm -qpi ../linux-out/*.rpm | grep -i version
```

### 7. Publikacja gałęzi serii

```bash
git push -u origin linux-packages-0.25.0
```

Push aktualizuje forka; jeśli nowa gałąź ma zostać domyślną, zmień ją w ustawieniach forka. Kolejne uruchomienie workflow użyje nowej serii.

**Uwaga:** workflow czyta nazwę gałęzi serii ze zmiennej `SERIES_BRANCH` na górze `.github/workflows/linux-packages.yml` (obecnie `linux-packages-0.24.1`). Przy przecięciu serii na gałąź o innej nazwie zmień tę wartość **w tym samym czasie** co `SERIES-BASE` — jedno miejsce w pliku, obie prace (`build` i `flatpak`) czytają tę zmienną. Notki wydania także czytają te dwa źródła (`SERIES-BASE` i `SERIES_BRANCH`), więc po aktualizacji obu nie trzeba nic poprawiać w heredocu z treścią notek — podmienią się same. Obie zmiany muszą jednak wylądować na **domyślnej gałęzi forka**: cron uruchamia workflow z gałęzi domyślnej, więc dopóki zaktualizowany `packaging/linux/SERIES-BASE` (wraz z odwołaniami do `SERIES_BRANCH`) i sama zmienna nie zostaną tam wypchnięte, automat dalej czyta starą bazę.

## Znane zastrzeżenia

- Flatpak: wewnętrzna piaskownica Chromium jest wyłączona (`ELECTRON_DISABLE_SANDBOX=1`); granicą bezpieczeństwa pozostaje piaskownica Flatpaka. Zypak z BaseApp 26.08 wywoływał SIGABRT w nadzorcy sidecara, dopóki nie wyłączyliśmy wewnętrznej piaskownicy (szczegóły w `packaging/flatpak/README.md`).
- Pakiety deb/rpm instalują się pod `/opt`.
- Brak automatycznych aktualizacji — nową wersję instaluje się ręcznie z kolejnego wydania.
- Pakiety są niepodpisane.
