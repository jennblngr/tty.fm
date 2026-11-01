# FTS5 is compiled into SQLite only with this build tag: always go through
# these targets (or pass -tags yourself).
TAGS    := sqlite_fts5
VERSION ?= $(shell git describe --tags --always --dirty 2>/dev/null || echo dev)
LDFLAGS := -s -w -X ttyfm/internal/app.Version=$(VERSION)

.PHONY: build run test vet

build:
	go build -tags $(TAGS) -ldflags "$(LDFLAGS)" -o bin/ttyfm ./cmd/ttyfm

run: build
	TTYFM_MUSIC_DIR=$${TTYFM_MUSIC_DIR:-$$HOME/Music} \
	TTYFM_DATA_DIR=$${TTYFM_DATA_DIR:-../data} \
	TTYFM_ADMIN_PASSWORD=$${TTYFM_ADMIN_PASSWORD:-admin} \
	./bin/ttyfm

test:
	go test -tags $(TAGS) ./...

vet:
	go vet -tags $(TAGS) ./...
