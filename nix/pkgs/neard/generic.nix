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
, autoPatchelfHook
, darwin
}:
{ version, rev ? null, sha256, cargoSha256, cargoBuildFlags ? [ ], neardRustPlatform ? rustPlatform }:
# based on https://github.com/ZentriaMC/neard-nix/blob/master/neardtynix
neardRustPlatform.buildRustPackage rec {
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
      # This branch: https://github.com/kuutamolabs/nearcore/tree/shutdown-patch-1.29.1-patch
      lib.optional (lib.versionOlder version "1.30.0-rc.5") (
        fetchpatch {
          name = "shutdown-patch-1.29.0-patch";
          url = "https://github.com/kuutamolabs/nearcore/commit/6253b22eb1458e148c33652a93bdd39c3bc9167f.patch";
          sha256 = "sha256-mvnANYlhKrSlnNAWIF9WmgeZzvD1wMwzwith8TZkvlg=";
        }
      )
    )

    # - Expected shutdown
    #   - https://github.com/near/nearcore/pull/7872
    # - Maintenance RPC
    #   - https://github.com/near/nearcore/pull/7887
    (
      lib.optional (lib.versionAtLeast version "1.30.0-rc.5") (
        fetchpatch {
          name = "maintenance_patch-1.30.0-rc.5";
          url = "https://github.com/yanganto/nearcore/commit/8671b358052461a26a42f90d4d8b30a5f8ba4a79.patch";
          sha256 = "sha256-QGn76On3j7WJZ3USTPs0VKE99jvNTL6w/QZ2T+zTDt4=";
        }
      )
    )

    # Enable tracked_shards
    (
      lib.optional (lib.versionAtLeast version "1.30.0-rc.5") (
        fetchpatch {
          name = "tracked_shard_patch-1.30.0-rc.5";
          url = "https://github.com/yanganto/nearcore/commit/1e291a6dec5291a2e3ba39c855b8d864e9ec2a1a.patch";
          sha256 = "sha256-hlJaHN2VTPF4wIihPb10WfIt6zAW9ZQ1AFsiTBePi6g=";
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
