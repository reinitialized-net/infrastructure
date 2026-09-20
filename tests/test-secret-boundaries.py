#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def main() -> None:
    expected = {
        "hosts/apps1.nix": ["GF_SECURITY_ADMIN_PASSWORD", "AUTHENTIK_SECRET_KEY"],
        "hosts/apps2.nix": [
            "MONGO_INITDB_ROOT_PASSWORD",
            "FORGEJO_ADMIN_API_TOKEN",
            "RI_REDIS_PASSWORD1",
            "JWT_SECRET",
            "INITIAL_PASSWORD",
        ],
        "hosts/apps3.nix": [
            "IMMICH_OIDC_CLIENT_SECRET",
            "PAPERLESS_SECRET_KEY",
            "PAPERLESS_ADMIN_PASSWORD",
            "PAPERLESS_REDIS",
            "IDM_ADMIN_PASSWORD",
        ],
        "hosts/db1.nix": ["POSTGRES_PASSWORD"],
    }
    for relative, names in expected.items():
        source = (ROOT / relative).read_text()
        for name in names:
            assert f"{name} = config.secrets" not in source
        assert "/var/lib/service-secrets/" in source

    vma = (ROOT / "library/generateVMAImage/default.nix").read_text()
    assert 'hashedPassword = lib.mkForce "!";' in vma
    assert "CREDENTIALS.txt" not in vma
    assert "randomPassword" not in vma

    dual_export = (ROOT / "library/makeDualExport.nix").read_text()
    assert "includeSecrets = false;" in dual_export
    assert "modules/secrets.example/" in dual_export

    db1 = (ROOT / "hosts/db1.nix").read_text()
    assert '"--aclfile"' in db1
    assert "/var/lib/service-secrets/valkey-users.acl" in db1

    tools = (ROOT / "hosts/devenv/devenvTools.nix").read_text()
    assert "opnsenseKeys" not in tools
    assert 'secretsEnvFile = "/var/lib/service-secrets/opnsense.env";' in tools

    make_configuration = (ROOT / "library/makeConfiguration.nix").read_text()
    assert "inTreeSecrets" not in make_configuration
    assert "modules/secrets/${host}.nix" not in make_configuration

    automation = (ROOT / "hosts/devenv/infraAutoUpdate.nix").read_text()
    assert 'liveSecretsSource = "${self}/modules/secrets"' not in automation

    devenv = (ROOT / "hosts/devenv.nix").read_text()
    assert 'initialPassword = "!";' not in devenv
    assert 'hashedPassword = "!";' in devenv
    assert 'username = "develop";' in devenv
    assert '"docker"' in devenv and '"wheel"' in devenv
    assert "openssh.authorizedKeys.keys" in devenv


if __name__ == "__main__":
    main()
