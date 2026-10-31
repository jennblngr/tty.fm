# FTS5 is compiled into SQLite only with this build tag: always go through
# these targets (or pass -tags yourself).
TAGS    := sqlite_fts5
VERSION ?= $(shell git describe --tags --always --dirty 2>/dev/null || echo dev)
LDFLAGS := -s -w -X selfstream/internal/app.Version=$(VERSION)

.PHONY: build run test vet

build:
	go build -tags $(TAGS) -ldflags "$(LDFLAGS)" -o bin/selfstream ./cmd/selfstream

run: build
	SELFSTREAM_MUSIC_DIR=$${SELFSTREAM_MUSIC_DIR:-$$HOME/Music} \
	SELFSTREAM_DATA_DIR=$${SELFSTREAM_DATA_DIR:-../data} \
	SELFSTREAM_ADMIN_PASSWORD=$${SELFSTREAM_ADMIN_PASSWORD:-admin} \
	./bin/selfstream

test:
	go test -tags $(TAGS) ./...

vet:
	go vet -tags $(TAGS) ./...
