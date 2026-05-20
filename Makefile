.PHONY: setup doctor update project recon dashboard

LAB_ROOT := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))

setup:
	./setup-recon-tools.sh

doctor:
	./tools/doctor.sh

update:
	./tools/update-lab.sh

project:
	@test -n "$(TARGET)" || (echo "Usage: make project TARGET=example.com" && exit 1)
	./target $(TARGET)

recon:
	@test -n "$(TARGET)" || (echo "Usage: make recon TARGET=example.com" && exit 1)
	./target --recon $(TARGET)

dashboard:
	./dashboard
