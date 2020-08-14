PREFIX=github.com/kwkoo
PACKAGE=webnotifications
OCP_PROJ=demo

GOPATH:=$(shell dirname $(realpath $(lastword $(MAKEFILE_LIST))))
GOBIN=$(GOPATH)/bin
COVERAGEOUTPUT=coverage.out
COVERAGEHTML=coverage.html
IMAGENAME="kwkoo/$(PACKAGE)"
VERSION="0.2"

.PHONY: run build clean test coverage image runcontainer
run:
	-@GOPATH=$(GOPATH) \
	GOBIN=$(GOBIN) \
	DOCROOT=$(GOPATH)/docroot \
	BUFFERSIZE=3 \
	PINGINTERVAL=10 \
	go run $(GOPATH)/src/$(PREFIX)/$(PACKAGE)/cmd/$(PACKAGE)/main.go

build:
	@echo "Building..."
	@GOPATH=$(GOPATH) \
	GOBIN=$(GOBIN) \
	go build -o $(GOBIN)/$(PACKAGE) $(PREFIX)/$(PACKAGE)/cmd/$(PACKAGE)

clean:
	rm -f \
	  $(GOPATH)/bin/$(PACKAGE) \
	  $(GOPATH)/pkg/*/$(PACKAGE).a \
	  $(GOPATH)/$(COVERAGEOUTPUT) \
	  $(GOPATH)/$(COVERAGEHTML)

test:
	@GOPATH=$(GOPATH) GOBIN=$(GOBIN) go clean -testcache
	@GOPATH=$(GOPATH) GOBIN=$(GOBIN) go test -race $(PREFIX)/$(PACKAGE)

coverage:
	@GOPATH=$(GOPATH) GOBIN=$(GOBIN) go test $(PREFIX)/$(PACKAGE) -cover -coverprofile=$(GOPATH)/$(COVERAGEOUTPUT)
	@GOPATH=$(GOPATH) GOBIN=$(GOBIN) go tool cover -html=$(GOPATH)/$(COVERAGEOUTPUT) -o $(GOPATH)/$(COVERAGEHTML)
	open $(GOPATH)/$(COVERAGEHTML)

dockerimage: 
	docker build --rm -t $(IMAGENAME):$(VERSION) $(GOPATH)
	docker tag $(IMAGENAME):$(VERSION) quay.io/$(IMAGENAME):$(VERSION)
	docker tag $(IMAGENAME):$(VERSION) quay.io/$(IMAGENAME):latest
	docker login quay.io
	docker push quay.io/$(IMAGENAME):$(VERSION)
	#docker push quay.io/$(IMAGENAME):latest

runcontainer:
	docker run \
	  --rm \
	  -it \
	  --name $(PACKAGE) \
	  -p 8080:8080 \
	  -e TZ=Asia/Singapore \
	  $(IMAGENAME):$(VERSION)

deployocp:
	oc new-project $(OCP_PROJ) || oc project $(OCP_PROJ)
	-rm -rf /tmp/ocp
	mkdir /tmp/ocp
	mkdir -p /tmp/ocp/.s2i/bin
	cp $(GOPATH)/scripts/s2i_assemble /tmp/ocp/.s2i/bin/assemble
	cp -r $(GOPATH)/docroot $(GOPATH)/src /tmp/ocp/
	oc import-image \
	  --confirm \
	  docker.io/centos/go-toolset-7-centos7:latest
	@/bin/echo -n "Waiting for Go imagestreamtag to be created..."
	@while true; do \
	  oc get istag go-toolset-7-centos7:latest 2>/dev/null 1>/dev/null;  \
	  if [ $$? -eq 0 ]; then /bin/echo "done"; break; fi; \
	  /bin/echo -n "."; \
	  sleep 1; \
	done
	oc new-build \
	  --name $(PACKAGE) \
	  --binary \
	  --labels=app=$(PACKAGE) \
	  -i go-toolset-7-centos7:latest
	oc start-build \
	  $(PACKAGE) \
	  --from-dir=/tmp/ocp \
	  --follow
	rm -rf /tmp/ocp

	oc new-app \
	  --name $(PACKAGE) \
	  -i $(PACKAGE) \
	  -e DOCROOT=/opt/app-root/docroot \
	  -e TZ=Asia/Singapore
	
	oc expose dc/$(PACKAGE) --port=8080
	oc expose svc/$(PACKAGE)
	@echo "Deployment successful"
	@echo "The application is now accessible at http://`oc get route/$(PACKAGE) -o jsonpath='{ .spec.host }'`"

cleanocp:
	-oc delete all -l app=$(PACKAGE) -n $(OCP_PROJ)
	-rm -rf /tmp/ocp