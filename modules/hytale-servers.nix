self: {
  config,
  pkgs,
  lib,
  ...
}: let
  inherit
    (lib)
    attrsets
    lists
    strings
    types
    mkOption
    mkEnableOption
    mkIf
    ;
  inherit (attrsets) mapAttrs mapAttrs' mapAttrsToList nameValuePair;
  inherit (strings) concatStrings;

  flakePkgs = self.packages."${pkgs.stdenv.hostPlatform.system}";

  cfg = config.services.hytale-servers;
in {
  options = let
    file = types.submodule (
      {
        name,
        config,
        ...
      }: {
        options = {
          name = mkOption {
            type = types.str;
            default = name;
            description = ''
              The name of the file.
            '';
            internal = true;
            readOnly = true;
            visible = false;
          };

          method = mkOption {
            type = types.enum [
              "copy"
              "symlink"
            ];
            default = "symlink";
            description = ''
              How to manage the target file.
              - "symlink": The target will be a symlink to the source in the store.
              - "copy": The source will be copied to the target.
              "symlink" may cause issues when read-write access is expected and does not support custom permissions,
              whereas "copy" imposes a disk space penalty.
            '';
            example = "copy";
          };

          source = mkOption {
            type = types.path;
            default = pkgs.writeText (baseNameOf name) config.text;
            description = ''
              Path of the source file or directory.
            '';
          };

          text = mkOption {
            type = types.nullOr types.lines;
            default = null;
            description = ''
              Text content of the file.
            '';
          };
        };
      }
    );

    hytaleServer = types.submodule (
      {
        name,
        config,
        ...
      }: {
        options = {
          enable = mkEnableOption "this Hytale server";

          name = mkOption {
            type = types.str;
            default = name;
            description = ''
              The name of the Hytale server.
            '';
            internal = true;
            readOnly = true;
            visible = false;
          };

          autoStart = mkOption {
            type = types.bool;
            default = false;
            description = ''
              Whether to start the server on boot.
              It is currently not recommended to set this option, as the service hangs when credentials are not present or expired.
            '';
            example = true;
          };

          assetsDir = mkOption {
            type = types.str;
            default = "${cfg.assetsDir}/${
              if (isNull config.version)
              then config.patchline
              else "${config.patchline}-${config.version}"
            }";
            description = ''
              The path to the server binary and assets.
            '';
            internal = true;
            readOnly = true;
            visible = false;
          };

          dataDir = mkOption {
            type = types.str;
            default = "${cfg.dataDir}/${name}";
            description = ''
              The path to the server data directory.
            '';
            internal = true;
            readOnly = true;
            visible = false;
          };

          listenAddress = mkOption {
            type = types.str;
            default = "0.0.0.0";
            description = ''
              The IP address to bind the server to.
            '';
            example = "127.0.0.1";
          };

          port = mkOption {
            type = types.int;
            default = 5520;
            description = ''
              The port which the server will listen to.
            '';
            example = 65535;
          };

          openFirewall = mkOption {
            type = types.bool;
            default = false;
            description = ''
              Whether to open the server port in the firewall.
            '';
            example = true;
          };

          restart = mkOption {
            type = types.enum [
              "no"
              "always"
              "on-success"
              "on-failure"
              "on-abnormal"
              "on-abort"
              "on-warning"
            ];
            default = "on-success";
            description = ''
              The condition under which to restart the server if it stops.
              This is the service's `Restart=` parameter.
              Note that this will cause the server to restart instead of stopping
              if the `/stop` command is issued on the server.
            '';
            internal = true;
            visible = false;
          };

          tmux.enable = mkOption {
            type = types.bool;
            default = false;
            description = ''
              Whether to run the server process in a tmux session.
            '';
            example = true;
          };

          patchline = mkOption {
            type = types.enum [
              "release"
              "pre-release"
            ];
            default = "release";
            description = ''
              The Hytale version patchline to follow.
            '';
            example = "pre-release";
          };

          version = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = ''
              The Hytale server version to use.
              It is highly recommended to NOT use this option as Hytale clients
              always follow the latest version. However, this option is available
              in case servers need to perform maintenance before upgrading.
              - This option will only work if the asset archive and server jar for the specified
              version have already been downloaded, as the latest version is the only one provided
              by the Hytale CDN.
              - This overrides `servers.<server>.patchline`, as it skips the
              Hytale downloader stage if set.
            '';
            visible = false;
          };

          acknowledgeVersionWarning = mkOption {
            type = types.bool;
            default = false;
            description = ''
              Do not warn when the `version` attribute is set.
            '';
            visible = false;
          };

          java = {
            package = mkOption {
              type = types.package;
              default = pkgs.javaPackages.compiler.temurin-bin.jre-25;
              description = ''
                The package to provide the JVM used by the server.
              '';
            };

            jvmOpts = mkOption {
              type = types.str;
              default = "";
              description = ''
                Additional flags to pass to the JVM.
              '';
              example = "-Xms4G -Xmx8G";
            };
          };

          files = mkOption {
            type = types.attrsOf file;
            default = {};
            description = ''
              Files to link from the Nix store into the server data directory upon server start.
              This can be used for declarative server configuration and plugin management.
            '';
          };
        };
      }
    );
  in {
    services.hytale-servers = {
      enable = mkEnableOption "Hytale server management";

      user = mkOption {
        type = types.str;
        default = "hytale";
        description = ''
          The name of the user account to own the Hytale servers.
          It's recommended to leave this as the default.
        '';
        internal = true;
        visible = false;
      };

      group = mkOption {
        type = types.str;
        default = "hytale";
        description = ''
          The name of the user group to own the Hytale servers.
          It's recommended to leave this as the default.
        '';
        internal = true;
        visible = false;
      };

      credentialsPath = mkOption {
        type = types.str;
        default = "/var/cache/hytale/credentials.json";
        description = ''
          The location to store the Hytale downloader credentials.
        '';
      };

      assetsDir = mkOption {
        type = types.str;
        default = "/var/lib/hytale/assets";
        description = ''
          The directory to store Hytale assets in.
          The newest available archive will be automatically downloaded upon server startup.
        '';
      };

      dataDir = mkOption {
        type = types.str;
        default = "/srv/hytale";
        description = ''
          The directory to store Hytale server data in.
          Server settings, mods, and universes will be stored in subfolders within this directory.
        '';
      };

      runtimeDir = mkOption {
        type = types.str;
        default = "/run/hytale";
        description = ''
          The directory to store Hytale server runtime data in.
        '';
        internal = true;
        readOnly = true;
        visible = false;
      };

      servers = mkOption {
        type = types.attrsOf hytaleServer;
        default = {};
        description = ''
          The Hytale server definitions.
        '';
      };
    };
  };

  config = mkIf cfg.enable (
    let
      enabledServers = attrsets.filterAttrs (_: server: server.enable) cfg.servers;
    in {
      users = {
        users.hytale = mkIf (cfg.user == "hytale") {
          description = "Hytale server service user";
          home = cfg.dataDir;
          homeMode = "770";
          createHome = true;
          isSystemUser = true;
          group = "hytale";
          # apparently needed since tmux parses commands via the login shell
          shell = pkgs.bash;
        };
        groups.hytale = mkIf (cfg.group == "hytale") {};
      };

      networking.firewall = let
        openedServers = attrsets.filterAttrs (_: c: c.openFirewall) enabledServers;
      in {
        allowedUDPPorts = lists.flatten (mapAttrsToList (_: c: c.port) openedServers);
      };

      systemd.tmpfiles.rules =
        [
          "d '${dirOf cfg.credentialsPath}' 0700 ${cfg.user} ${cfg.group}"
          "d '${cfg.assetsDir}' 0700 ${cfg.user} ${cfg.group}"
        ]
        ++ mapAttrsToList (
          _: server: "d '${server.dataDir}' 0770 ${cfg.user} ${cfg.group} - -"
        )
        enabledServers;

      systemd.sockets = let
        targetServers = attrsets.filterAttrs (_: server: !server.tmux.enable) cfg.servers;

        mkHytaleServerSocket = server: {
          inherit (server) enable;

          requires = ["hytale-server-${server.name}.service"];
          partOf = ["hytale-server-${server.name}.service"];

          socketConfig = {
            ListenFIFO = "${cfg.runtimeDir}/${server.name}.stdin";
            SocketMode = "0660";
            SocketUser = cfg.user;
            SocketGroup = cfg.group;
            RemoveOnStop = true;
            FlushPending = true;
          };
        };
      in
        mapAttrs' (
          _: server: nameValuePair "hytale-server-${server.name}" (mkHytaleServerSocket server)
        )
        targetServers;

      systemd.services = let
        hytaleDownloaderService = {
          description = "Hytale Downloader Service (%I patchline)";

          wants = ["network-online.target"];
          # make service run serially, so that multiple access tokens aren't requested at the same time
          after = ["hytale-downloader@.service" "network-online.target"];

          script = let
            hytaleDownloader = lib.getExe flakePkgs.hytale-downloader;
            unzip = lib.getExe pkgs.unzip;
            jq = lib.getExe pkgs.jq;
          in ''
            set -eo pipefail

            CREDENTIALS_PATH="${cfg.credentialsPath}"

            patchline=$1

            hytale_downloader() {
              "${hytaleDownloader}" \
                -skip-update-check \
                -patchline "$patchline" \
                -credentials-path "$CREDENTIALS_PATH" \
                "$@"
            }

            request_auth() {
              auth_out="$(mktemp -up "$RUNTIME_DIRECTORY" auth.XXXXXX)"
              mkfifo "$auth_out"; chmod 700 "$auth_out"

              # causes the downloader to request authentication
              hytale_downloader -print-version > "$auth_out"

              rm "$auth_out"
            }

            try_hytale_downloader() {
              if output="$(hytale_downloader "$@")"; then
                echo "$output"
              else
                rm "$CREDENTIALS_PATH"; request_auth

                hytale_downloader "$@"
              fi
            }

            # check if the token has expired, and refresh it if so
            if [ -e "$CREDENTIALS_PATH" ]; then
              auth_expires_at="$("${jq}" .expires_at "$CREDENTIALS_PATH")"
              current_time="$(date +%s)"
              if [ "$current_time" -ge "$auth_expires_at" ]; then
                rm "$CREDENTIALS_PATH"; request_auth
              fi
            else
              request_auth
            fi

            game_version="$(try_hytale_downloader -print-version)"
            assets_dir="${cfg.assetsDir}/$patchline-$game_version"

            if [ ! -d "$assets_dir" ]; then
              download_dir=$(mktemp -d)
              try_hytale_downloader -download-path "$download_dir/assets.zip"

              mkdir -p "$assets_dir"
              ${unzip} "$download_dir/assets.zip" -d "$assets_dir"
              rm -r "$download_dir"
            fi

            ln -sf "$patchline-$game_version" "${cfg.assetsDir}/$patchline"
          '';
          scriptArgs = "%I";
          enableStrictShellChecks = true;

          serviceConfig = {
            Type = "oneshot";

            TimeoutStartSec = "10m";

            User = cfg.user;
            Group = cfg.group;
            StandardOutput = "journal";
            StandardError = "journal";
            RuntimeDirectory = "hytale-downloader";
            RuntimeDirectoryPreserve = false;
            RuntimeDirectoryMode = "700";
            UMask = "0077";
          };
        };

        mkServerSessionScripts = server: let
          socketPath = "${cfg.runtimeDir}/${server.name}.sock";
          fifoPath = "${cfg.runtimeDir}/${server.name}.stdin";
          tmux = "${lib.getExe pkgs.tmux} -S ${socketPath}";

          serverLaunchCommand = with server; ''
            ${lib.getExe java.package} \
              -XX:AOTCache="${assetsDir}/Server/HytaleServer.aot" \
              ${java.jvmOpts} \
              -jar "${assetsDir}/Server/HytaleServer.jar" \
              --assets "${assetsDir}/Assets.zip" \
              --bind ${listenAddress}:${toString port}
          '';

          sessionStart =
            if server.tmux.enable
            then ''
              ${tmux} new-session -d "${serverLaunchCommand}"
            ''
            else serverLaunchCommand;

          # allow the hytale group to access the tmux session
          sessionPostStart = lib.optionalString server.tmux.enable ''
            chmod 660 ${socketPath}
          '';

          sessionStop =
            if server.tmux.enable
            then ''
              if ! ${tmux} has-session; then exit; fi
              ${tmux} send-keys C-u stop Enter
              while ${tmux} has-session; do sleep 1s; done
            ''
            else ''
              echo stop > ${fifoPath}
              while kill -0 "$1" 2>/dev/null; do sleep 1s; done
            '';
        in {
          start = pkgs.writeShellScript "hytale-server-${server.name}-start" sessionStart;
          postStart = pkgs.writeShellScript "hytale-server-${server.name}-post-start" sessionPostStart;
          stop = pkgs.writeShellScript "hytale-server-${server.name}-stop" sessionStop;
        };

        mkHytaleServerService = server: let
          optionalDownloaderDependency = lib.optional (isNull server.version) "hytale-downloader@${server.patchline}.service";
          optionalSocketDependency = lib.optional (!server.tmux.enable) "hytale-server-${server.name}.socket";

          sessionScripts = mkServerSessionScripts server;
        in {
          inherit (server) enable;

          description = "Hytale Server ${server.name}";
          wantedBy = lib.mkIf server.autoStart ["default.target"];
          requires = optionalSocketDependency ++ optionalDownloaderDependency;
          partOf = optionalSocketDependency;
          after = ["network.target"] ++ optionalDownloaderDependency;

          path = with pkgs; [
            # infocmp
            ncurses
            # chmod
            coreutils
          ];

          serviceConfig = {
            Type =
              if server.tmux.enable
              then "forking"
              else "simple";
            ExecStart = sessionScripts.start;
            ExecStartPost = sessionScripts.postStart;
            ExecStop = "${sessionScripts.stop} $MAINPID";
            StandardInput =
              if server.tmux.enable
              then "null"
              else "socket";
            StandardOutput =
              if server.tmux.enable
              then "null"
              else "journal";
            StandardError =
              if server.tmux.enable
              then "null"
              else "journal";
            Restart = server.restart;

            User = cfg.user;
            Group = cfg.group;
            WorkingDirectory = server.dataDir;
            RuntimeDirectory = lib.removePrefix "/run/" cfg.runtimeDir;
            RuntimeDirectoryPreserve = "restart";

            # hardening
            CapabilityBoundingSet = [""];
            DeviceAllow = [""];
            LockPersonality = true;
            PrivateDevices = true;
            PrivateTmp = true;
            PrivateUsers = true;
            ProtectClock = true;
            ProtectControlGroups = true;
            ProtectHome = true;
            ProtectHostname = true;
            ProtectKernelLogs = true;
            ProtectKernelModules = true;
            ProtectKernelTunables = true;
            ProtectProc = "invisible";
            RestrictAddressFamilies =
              [
                "AF_INET"
                "AF_INET6"
              ]
              ++ lib.optional server.tmux.enable "AF_UNIX";
            RestrictNamespaces = true;
            RestrictRealtime = true;
            RestrictSUIDSGID = true;
            SystemCallArchitectures = "native";
            UMask = "0007";
          };
        };
      in
        {
          "hytale-downloader@" = hytaleDownloaderService;
        }
        // mapAttrs' (
          _: server: nameValuePair "hytale-server-${server.name}" (mkHytaleServerService server)
        )
        cfg.servers;

      # |                                                             |
      # |                                                             |
      # \_________________________________  __________________________/
      #                                   |/
      system.activationScripts.linkHytaleServerFiles = let
        cmp = "${pkgs.diffutils}/bin/cmp";
        lndir = lib.getExe pkgs.xorg.lndir;
        sudo = lib.getExe pkgs.sudo;

        gcRootsPath = "/nix/var/nix/gcroots/hytale";

        mkServerFilesPackage = server:
          pkgs.runCommandLocal "hytale-server-${server.name}-files" {} (
            ''
              mkdir -p $out

              linkFile() {
                method=$1
                source=$2
                destination=$3

                pkgDestination="$(realpath -m "$out/$destination")"

                mkdir -p "$(dirname "$pkgDestination")"
                if [ "$method" == "symlink" ]; then
                  if [ -d "$source" ]; then
                    ${lndir} -silent "$source" "$pkgDestination"
                  else
                    ln -sfn "$source" "$pkgDestination"
                  fi
                elif [ "$method" == "copy" ]; then
                  cp -r "$source" "$pkgDestination"
                fi
              }
            ''
            + concatStrings (
              mapAttrsToList (_: file: ''
                linkFile "${file.method}" "${file.source}" "${file.name}"
              '')
              server.files
            )
          );

        serverFilesPackages = mapAttrs (_: server: mkServerFilesPackage server) enabledServers;

        genServerPackagesCommands = f:
          concatStrings (
            mapAttrsToList (serverName: pkg: f enabledServers."${serverName}" pkg) serverFilesPackages
          );

        cleanup = pkgs.writeShellScript "cleanup" ''
          baseDir="$1"
          destination="$2"
          shift 2; files=("$@")

          for file in "''${files[@]}"; do
            prevFile="$baseDir/$file"
            targetFile="$destination/$file"
            targetBaseDir="$(dirname "$targetFile")"

            if ${cmp} -s "$prevFile" "$targetFile"; then rm -rf "$targetFile"; fi

            # remove the directories that have been made empty unless it's the server data root
            if [ -d "$targetBaseDir" ] && [ "$targetBaseDir" != "$destination" ]; then
              rmdir -p --ignore-fail-on-non-empty "$targetBaseDir"
            fi
          done
        '';

        link = pkgs.writeShellScript "link" ''
          LINK_PATTERN="${lib.escapeShellArg builtins.storeDir}/*-hytale-server-*-files/*"

          baseDir="$1"
          destination="$2"
          shift 2; files=("$@")

          warnSkipFile() {
            echo "Not overwriting existing file: $1" >&2
          }

          for file in "''${files[@]}"; do
            srcFile="$baseDir/$file"
            dstFile="$destination/$file"

            if [ -L "$srcFile" ]; then
              if [ -e "$dstFile" ]; then
                # if it's identical to the one that's already there, don't bother
                if [ "$(readlink -e "$srcFile")" = "$(readlink -e "$dstFile")" ]; then continue
                # if it looks like a stale link to an old file, get rid of it
                elif [ ! "$(readlink "$dstFile")" == "$LINK_PATTERN" ]; then
                  warnSkipFile "$dstFile"
                  continue
                fi
              fi

              mkdir -p "$(dirname "$dstFile")"
              ln -Tsf "$srcFile" "$dstFile"
            else
              if [ -e "$dstFile" ]; then
                # if it's identical to the one that's already there, don't bother
                if ${cmp} -s "$srcFile" "$dstFile"; then continue; fi
                warnSkipFile "$dstFile"
                continue
              fi

              rm -rf "$dstFile"
              mkdir -p "$(dirname "$dstFile")"
              cp -r "$srcFile" "$dstFile"
              chmod -R ug+w "$dstFile"
            fi
          done
        '';

        makeServerFiles = pkgs.writeShellScript "make-hytale-server-files" ''
          umask 007

          ${genServerPackagesCommands (
            server: pkg: ''
              find -L "${gcRootsPath}/${pkg.name}" \( -type f -or -type l \) -printf '%P\0' \
                | xargs -0 "${cleanup}" "${gcRootsPath}/${pkg.name}" "${server.dataDir}"

              find -L "${pkg}" \( -type f -or -type l \) -printf '%P\0' \
                | xargs -0 "${link}" "${pkg}" "${server.dataDir}"
            ''
          )}
        '';

        updateGcRoots = pkgs.writeShellScript "update-hytale-gc-roots" ''
          if [ -d "${gcRootsPath}" ]; then rm -rf "${gcRootsPath}"; fi
          mkdir -p "${gcRootsPath}"

          ${genServerPackagesCommands (
            _: pkg: ''
              ln -s "${pkg}" "${gcRootsPath}/${pkg.name}"
            ''
          )}
        '';
      in {
        text = ''
          ${sudo} -u hytale ${makeServerFiles}
          ${updateGcRoots}
        '';
      };

      warnings = let
        targetServers =
          attrsets.filterAttrs (
            _: c: !isNull c.version && !c.acknowledgeVersionWarning
          )
          enabledServers;
      in
        attrsets.mapAttrsToList (_: server: ''
          Hytale server ${server.name} has `version` set to `${server.version}`. It is not recommended to pin the server version. Please remove this field or set
          `acknowledgeVersionWarning = true;` in your server's attributes to disable this warning.
        '')
        targetServers;
    }
  );
}
