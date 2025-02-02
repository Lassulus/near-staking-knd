{ fetchFromGitHub
, fetchpatch
, zlib
, openssl
, pkg-config
, protobuf
, rustPlatform
, llvmPackages
, lib
, stdenv
, darwin
}:
{ version, rev ? null, sha256, cargoSha256, cargoBuildFlags ? [ ] }:
# based on https://github.com/ZentriaMC/neard-nix/blob/master/neardtynix
rustPlatform.buildRustPackage rec {
  pname = "neard";
  inherit version;

  # https://github.com/near/nearcore/tags
  src = fetchFromGitHub {
    owner = "near";
    repo = "nearcore";
    # there is also a branch for this version number, so we need to be explicit
    rev = if rev == null then "refs/tags/${version}" else rev;
    inherit sha256;
  };

  inherit cargoSha256;

  patches = [ ];

  cargoPatches = [
    # Stateviewer has a test dependency on the wasm contracts.
    # Since we are not building tests, we can skip those.
    ./0001-make-near-test-contracts-optional.patch

    # - Expected shutdown
    #   - https://github.com/near/nearcore/pull/7872
    # - Maintenance RPC
    #   - https://github.com/near/nearcore/pull/7887
    (
      lib.optional (lib.versionOlder version "1.30.0-rc.5") (
        fetchpatch {
          name = "maintenance_patch-1.30.0-rc.5";
          url = "https://github.com/kuutamolabs/nearcore/commit/8671b358052461a26a42f90d4d8b30a5f8ba4a79.patch";
          sha256 = "sha256-QGn76On3j7WJZ3USTPs0VKE99jvNTL6w/QZ2T+zTDt4=";
        }
      )
    )

    # Remove test dependency on contract
    # Since we are not building tests, we can skip those.
    (
      lib.optional (lib.versionAtLeast version "1.31.0-rc.1") (
        ./0002-rm-near-test-contracts.patch
      )
    )

    # Limit RocksDB file open numbers
    (
      lib.optional (lib.versionAtLeast version "1.31.0-rc.1") (
        ./0003-rocksdb-max-open.patch
      )
    )

    # patch cargo lock version
    (
      lib.optional (lib.versionAtLeast version "1.31.0-rc.2") (
        ./0004-1.30.0-rc.2-cargo.lock.patch
      )
    )

    (
      lib.optional (lib.versionAtLeast version "1.31.0-rc.1") (
        fetchpatch {
          name = "maintenance_patch-1.31.0-rc.5";
          url = "https://github.com/kuutamolabs/nearcore/commit/e045bee17716140e53dcb53bcae43bc4f3c4d8d7.patch";
          sha256 = "sha256-fKX+LvASNa0FR97qquUxIDXv91KKYKMaKRTNPuQF41w=";
        }
      )
    )
  ];

  postPatch = ''
    substituteInPlace neard/build.rs \
      --replace 'get_git_version()?' '"nix:${version}"'
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    $out/bin/neard --version | grep -q "nix:${version}"
  '';

  CARGO_PROFILE_RELEASE_CODEGEN_UNITS = "1";
  CARGO_PROFILE_RELEASE_LTO = "fat";
  NEAR_RELEASE_BUILD = "release";
  inherit cargoBuildFlags;

  OPENSSL_NO_VENDOR = 1; # we want to link to OpenSSL provided by Nix

  buildAndTestSubdir = "neard";
  doCheck = false;

  buildInputs = [
    zlib
    openssl
  ] ++ lib.optional stdenv.isDarwin darwin.apple_sdk.frameworks.DiskArbitration;

  nativeBuildInputs = [
    pkg-config
    protobuf
  ];

  LIBCLANG_PATH = "${llvmPackages.libclang.lib}/lib";
  BINDGEN_EXTRA_CLANG_ARGS = "-isystem ${llvmPackages.libclang.lib}/lib/clang/${lib.getVersion llvmPackages.clang}/include";

  meta = with lib; {
    description = "Reference client for NEAR Protocol";
    homepage = "https://github.com/near/nearcore";
    license = licenses.gpl3;
    maintainers = with maintainers; [ mic92 ];
    platforms = platforms.unix;
  };
}
