.PHONY: setup doctor update project recon

LAB_ROOT := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))

setup:
	./setup-recon-tools.sh

doctor:
	./tools/doctor.sh

update:
	./tools/update-lab.sh

project:
	@test -n "$(TARGET)" || (echo "Usage: make project TARGET=example.com" && exit 1)
	./start-project.sh $(TARGET)

recon:
	@test -n "$(TARGET)" || (echo "Usage: make recon TARGET=example.com" && exit 1)
	./start-project.sh --recon $(TARGET)
