{
  description = "Provides a nix-shell environment for SIG DevOps development";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};

        # This is the Python version that will be used.
        myPython = pkgs.python3;

        pythonWithPkgs = myPython.withPackages (pythonPkgs: with pythonPkgs; [
          # This list contains tools for Python development.
          # You can also add other tools, like black.
          #
          # Note that even if you add Python packages here like PyTorch or Tensorflow,
          # they will be reinstalled when running `pip -r requirements.txt` because
          # virtualenv is used below in the shellHook.
          ipython
          pip
          setuptools
          virtualenvwrapper
          wheel
        ]);

        lib-path = with pkgs; lib.makeLibraryPath [
          libffi
          openssl
          stdenv.cc.cc
          # If you want to use CUDA, you should uncomment this line.
          # linuxPackages.nvidia_x11
        ];
      in
      with pkgs;
      {
        shell = inSite:
          let
            features = {
              aws = {
                defaults = {
                  aws = {
                    enabled = false;
                    profile = "default";
                  };
                };

                buildInputs = [
                  awscli2
                  ssm-session-manager-plugin
                  git-remote-codecommit
                  amazon-ecs-cli
                ];

                env = {
                  AWS_PROFILE = "${site.aws.profile}";
                };
              };

              awsSam = {
                defaults = {
                  awsSam = {
                    enabled = false;
                  };
                };

                buildInputs = [
                  aws-sam-cli
                ];
              };
            };

            defaults = features.aws.defaults // features.awsSam.defaults;
            site = defaults // inSite;

            featureExtras.aws = if site.aws.enabled then features.aws.buildInputs else [ ];
            featureExtras.awsSam = if site.awsSam.enabled then features.awsSam.buildInputs else [ ];

            extras.buildInputs = featureExtras.aws ++ featureExtras.awsSam;

            mixin = if site.aws.enabled then features.aws.env else { };

            glibcLocaleArchivePath = if pkgs.glibcLocales != null then "${pkgs.glibcLocales}/lib/locale/locale-archive" else "";
          in
          {
            buildInputs = [
              # Basics
              git
              wget
              curl
              nmap
              dnsutils
              vim
              entr
              jq
              parallel
              unzip
              which
              just
              watchexec

              # other packages needed for compiling python libs
              readline
              libffi
              openssl
              glibcLocalesUtf8

              # unfortunately needed because of messing with LD_LIBRARY_PATH below
              openssh
              rsync

              # Python
              pipenv
              pythonWithPkgs
            ] ++ extras.buildInputs;

            shellHook = ''
              # Allow the use of wheels.
              SOURCE_DATE_EPOCH=$(date +%s)

              # Augment the dynamic linker path
              export "LD_LIBRARY_PATH=$LD_LIBRARY_PATH:${lib-path}"

              PIP_IGNORE_INSTALLED=1 pipenv sync
              . "$(pipenv --venv)/bin/activate"

              echo "Entered ${site.name} development environment."
              export PS1="\n\[\033[1;32m\][nix-shell:\w] $AWS_PROFILE \$\[\033[0m\] ";

              [ -n "${glibcLocaleArchivePath}" ] && export LOCALE_ARCHIVE="${glibcLocaleArchivePath}";
            '';

            # This is needed to prevent ansible failing due to locale settings.
            # if glibcLocales != null LOCALE_ARCHIVE = "${glibcLocales}/lib/locale/locale-archive";

            # LC_ALL="C.UTF-8";
            LC_ALL = "en_US.utf8";
            LC_LANG = "en_US.utf8";
          } // mixin;
      }
    );
}
