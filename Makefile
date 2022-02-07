IMAGE=dvitali/chasquid
VERSION=$(shell git describe --tags --dirty --always)

build:
	docker build \
		-t "$(IMAGE):$(VERSION)" \
		.

push:
	docker push "$(IMAGE):$(VERSION)"

run:
	docker run \
		--rm \
		--name chasquid \
		-v "$$PWD/data_example/rspamd_connection:/run/secrets/rspamd_connection" \
		"$(IMAGE):$(VERSION)"

run-debug:
	docker run \
		--rm \
		--name chasquid-debug \
		--entrypoint=/bin/bash \
		-it \
		-v "$$PWD/data_example/rspamd_connection:/run/secrets/rspamd_connection" \
		"$(IMAGE):$(VERSION)"


debug:
	docker run --entrypoint=sh --rm -it "$(IMAGE):$(VERSION)"
