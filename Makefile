WIDGET_ID  := com.github.pomodoro-todo
INSTALL_DIR := $(HOME)/.local/share/plasma/plasmoids/$(WIDGET_ID)
MOBILE_DIR  := mobile

.PHONY: all install reload clean \
        mobile-get mobile-build-apk mobile-build-linux mobile-run \
        mobile-clean mobile-analyze

# ── Plasmoid ──────────────────────────────────────────────────────────────────

all: install

install:
	@bash install.sh

reload: install
	kquitapp6 plasmashell && kstart plasmashell

clean:
	@echo "Removing installed plasmoid…"
	rm -rf "$(INSTALL_DIR)"
	@echo "Removing compiled translations…"
	find contents/locale -name "*.mo" -delete
	@echo "Done."

# ── Flutter mobile ────────────────────────────────────────────────────────────

mobile-get:
	cd $(MOBILE_DIR) && flutter pub get

mobile-build-apk: mobile-get
	cd $(MOBILE_DIR) && flutter build apk --release --split-per-abi

mobile-build-linux: mobile-get
	cd $(MOBILE_DIR) && flutter build linux --release

mobile-run: mobile-get
	cd $(MOBILE_DIR) && flutter run

mobile-analyze: mobile-get
	cd $(MOBILE_DIR) && flutter analyze

mobile-clean:
	cd $(MOBILE_DIR) && flutter clean

# ── Combined clean ────────────────────────────────────────────────────────────

clean-all: clean mobile-clean
