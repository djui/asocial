#!/bin/zsh
# Builds the app for TestFlight and uploads it: archives Release for iOS, then exports the archive
# with ExportOptions.plist, which signs it for App Store Connect and uploads it.
#
#   scripts/testflight.sh            archive and upload the working tree
#   scripts/testflight.sh 71         ... with build number 71 (else Xcode's, bumped on a clash)
#   scripts/testflight.sh --export   upload the archive from the last run again (after a failed upload)
#
# Authenticates with an App Store Connect API key, so no Xcode account session is needed:
# the key file is read from $TESTFLIGHT_KEY (default ~/.appstoreconnect/private_keys/AuthKey_<id>.p8),
# its id from $TESTFLIGHT_KEY_ID and the issuer from $TESTFLIGHT_ISSUER_ID. Run from the repo root.
set -euo pipefail

key_id=${TESTFLIGHT_KEY_ID:-67J574H736}
issuer_id=${TESTFLIGHT_ISSUER_ID:-69a6de6e-5f69-47e3-e053-5b8c7c11a4d1}
key=${TESTFLIGHT_KEY:-$HOME/.appstoreconnect/private_keys/AuthKey_$key_id.p8}
root=$(cd "$(dirname "$0")/.." && pwd)
archive=$root/build/Asocial.xcarchive
export_dir=$root/build/export

if [[ ! -r $key ]]; then
  echo "testflight: can't read the App Store Connect API key at $key" >&2
  echo "Download it from App Store Connect › Users and Access › Integrations › App Store Connect API," >&2
  echo "put it there (chmod 700 on the folders, 600 on the file) or point TESTFLIGHT_KEY at it." >&2
  exit 1
fi

# xcodebuild wants an absolute key path.
auth=(-allowProvisioningUpdates -authenticationKeyPath "${key:A}" -authenticationKeyID "$key_id" -authenticationKeyIssuerID "$issuer_id")

if [[ ${1:-} != --export ]]; then
  build=()
  [[ -n ${1:-} ]] && build=(CURRENT_PROJECT_VERSION="$1")
  echo "testflight: archiving $(git -C "$root" rev-parse --short HEAD)${1:+ as build $1}…"
  rm -rf "$archive"
  xcodebuild archive -project "$root/Asocial.xcodeproj" -scheme Asocial \
    -destination 'generic/platform=iOS' -archivePath "$archive" -quiet "${auth[@]}" "${build[@]}"
fi

echo "testflight: uploading…"
rm -rf "$export_dir"
xcodebuild -exportArchive -archivePath "$archive" -exportOptionsPlist "$root/ExportOptions.plist" \
  -exportPath "$export_dir" "${auth[@]}" | grep -E 'Upload succeeded|error|EXPORT (SUCCEEDED|FAILED)' || true
echo "testflight: done. The build shows in App Store Connect › TestFlight once processed (a few minutes)."
