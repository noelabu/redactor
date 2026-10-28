.PHONY: all build test cert app install run reset-tcc clean

all: test app

# Compile only (debug).
build:
	swift build

test:
	swift test

# Create the "Redactor Local Signing" identity in the login keychain (no-op if it exists).
# A stable signature keeps Screen Recording permission across rebuilds.
cert:
	scripts/create-signing-cert.sh

# Release build into build/Redactor.app, signed.
app: cert
	./build.sh

# Build, install to ~/Applications and launch.
install: cert
	./build.sh --install

# Launch the installed app without rebuilding.
run:
	open "$(HOME)/Applications/Redactor.app"

# Reset Screen Recording / Desktop permissions, then build, install and launch.
reset-tcc: cert
	./build.sh --reset-tcc --install

# Remove SwiftPM and app build output.
clean:
	rm -rf .build build
