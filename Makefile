.POSIX:

CRYSTAL = crystal
CRFLAGS =

all: bin/genapi .phony
	bin/genapi openapi/v1.40.yaml > src/docker/client/v1.40.cr
	bin/genapi openapi/v1.41.yaml > src/docker/client/v1.41.cr
	bin/genapi openapi/v1.42.yaml > src/docker/client/v1.42.cr
	bin/genapi openapi/v1.43.yaml > src/docker/client/v1.43.cr

bin/genapi: bin/genapi.cr lib/swagger/src/* src/generator.cr src/generator/*
	$(CRYSTAL) build $(CRFLAGS) -o bin/genapi bin/genapi.cr

.phony:
