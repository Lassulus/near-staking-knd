#!/usr/bin/env python3

import os
import json
import subprocess
import time
from pathlib import Path
import pytest

from command import Command
from consul import Consul
from kuutamod import Kuutamod, set_kuutamoctl
from ports import Ports
from prometheus import query_prometheus_endpoint
from setup_localnet import NearNetwork
from typing import Any, List
from note import note, Section


def work_with_neard_versions(
    versions: List[str],
) -> Any:
    return pytest.mark.skipif(
        os.environ.get("NEARD_VERSION") not in versions,
        reason=f"Not suitable neard for current test, this test only for {versions}",
    )


@work_with_neard_versions(["1.29.0"])
def test_maintenance_shutdown(
    kuutamod: Path,
    kuutamoctl: Path,
    command: Command,
    consul: Consul,
    near_network: NearNetwork,
    ports: Ports,
) -> None:
    set_kuutamoctl(kuutamoctl)

    kuutamods = []
    for idx in range(2):
        kuutamods.append(
            Kuutamod.run(
                neard_home=near_network.home / f"kuutamod{idx}",
                kuutamod=kuutamod,
                ports=ports,
                near_network=near_network,
                command=command,
                consul=consul,
            )
        )
    leader = None
    follower = None

    with Section("leader election"):
        while leader is None:
            for idx, k in enumerate(kuutamods):
                res = query_prometheus_endpoint("127.0.0.1", k.exporter_port)
                if res.get('kuutamod_state{type="Validating"}') == "1":
                    note(f"leader is kuutamo{idx}")
                    leader = kuutamods[idx]
                    del kuutamods[idx]
                    follower = kuutamods.pop()
                    break
                time.sleep(0.1)
        proc = command.run(
            [
                str(kuutamoctl),
                "--json",
                "--consul-url",
                consul.consul_url,
                "active-validator",
            ],
            stdout=subprocess.PIPE,
        )
        assert proc.stdout
        print(proc.stdout)
        data = json.load(proc.stdout)
        assert data.get("ID")
        assert proc.wait() == 0
        assert follower is not None

        # Check if neard processes use correct specified ports
        leader.wait_validator_port()
        follower.wait_voter_port()

        assert len(kuutamods) == 0 and follower is not None
        follower_res = follower.metrics()
        assert follower_res['kuutamod_state{type="Validating"}'] == "0"

    with Section("test maintenance shutdown on follower"):
        pid = follower.neard_pid()
        assert pid is not None

        follower.execute_command(
            "maintenance-shutdown",
            "1",  # Use one block window for maintenance shutdown in test
        )

        start = time.perf_counter()

        while True:
            new_pid = follower.neard_pid()
            if pid != new_pid:
                break
            time.sleep(0.1)
        duration = time.perf_counter() - start
        note(f"follower restart time {duration}")

    with Section("test maintenance shutdown on leader"):
        pid = leader.neard_pid()
        assert pid is not None

        leader.execute_command(
            "maintenance-shutdown",
            "1",  # Use one block window for maintenance shutdown in test
        )

        note("checking on leader restart and keep producing block")
        check = 0
        while not leader.check_blocking():
            check += 1
            if check > 10:
                note("leader did not restart correctly")
                assert False
