D2 ?= d2
D2FLAGS := --layout=elk --theme=0 --dark-theme=200 --pad=24

DIAGRAMS := $(patsubst %.d2,%.svg,$(wildcard docs/diagrams/*.d2))
ANIMATED := docs/diagrams/frame-journey.svg docs/diagrams/chaos-proof.svg

.PHONY: diagrams
diagrams: $(DIAGRAMS) ## Render every D2 diagram to SVG

$(ANIMATED): D2FLAGS += --animate-interval=2000

docs/diagrams/%.svg: docs/diagrams/%.d2
	$(D2) $(D2FLAGS) $< $@
