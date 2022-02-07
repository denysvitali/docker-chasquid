IMAGE=dvitali/chasquid
VERSION=$(shell git describe --tags --dirty --always)

build:
	docker build \
		-t "$(IMAGE):$(VERSION)" \
		.

push:
	docker push "$(IMAGE):$(VERSION)"

debug:
	docker run --entrypoint=sh --rm -it "$(IMAGE):$(VERSION)"
