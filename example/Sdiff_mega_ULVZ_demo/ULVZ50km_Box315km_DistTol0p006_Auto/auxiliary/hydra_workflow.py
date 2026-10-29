#!/usr/bin/env python3
"""Advance this case through Slurm afterok dependencies without polling jobs."""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
from datetime import datetime, timezone

ROOT = Path(__file__).resolve().parent.parent
RUN = ROOT / "WORK/Hydra"
STATE = RUN / "workflow.json"
STEPS = {3: "step3_submit_specfem_mesh_gen.sh", 7: "step7_extract_injected_waves.sh",
         8: "step8_specfem_solver.sh", 9: "step9_coupling.sh",
         10: "step10_assemble_3d_sem_dsm_synthetics.sh", 11: "step11_rotate_synthetics_zrt.sh"}


def save(state):
    state["updated_utc"] = datetime.now(timezone.utc).isoformat()
    temporary = STATE.with_suffix(".tmp")
    temporary.write_text(json.dumps(state, indent=2) + "\n")
    temporary.replace(STATE)


def run_step(number, state):
    result = subprocess.run(["bash", str(ROOT / STEPS[number])], cwd=ROOT,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    (RUN / f"step{number}.log").write_text(result.stdout)
    print(result.stdout, flush=True)
    if result.returncode:
        state["status"] = f"failed_preparing_step{number}"
        save(state)
        raise RuntimeError(f"Step {number} failed; see {RUN / f'step{number}.log'}")
    return result.stdout


def schedule(number, dependency, state):
    result = subprocess.run(["sbatch", "--parsable", f"--dependency=afterok:{dependency}",
                             str(RUN / "run_next_stage.sbatch"), str(number)], cwd=ROOT,
                            check=True, stdout=subprocess.PIPE, text=True)
    job = result.stdout.strip().split(";")[0]
    if not job.isdigit():
        raise RuntimeError(f"Unexpected sbatch response: {result.stdout!r}")
    state["jobs"][f"prepare_step{number}"] = job
    save(state)
    print(f"Queued preparation for step {number}: {job}, after successful job {dependency}", flush=True)


def finalize_source_outputs(state):
    target = state.get("completion_output_dir")
    if not target:
        return
    if Path(target).name != target or not target.startswith("OUTPUT_FILES_"):
        raise RuntimeError("Invalid completion output directory")
    current = ROOT / "OUTPUT_FILES"
    destination = ROOT / target
    if destination.exists():
        raise RuntimeError(f"Output destination already exists: {destination}")
    import shutil
    shutil.copy2(ROOT / "WORK/SPECFEM3D/DATA/CMTSOLUTION", current / "CMTSOLUTION")
    current.rename(destination)
    state["result_directory"] = str(destination)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["start", "advance", "status"])
    parser.add_argument("stage", nargs="?", type=int)
    args = parser.parse_args()
    RUN.mkdir(parents=True, exist_ok=True)
    if args.action == "status":
        if not STATE.exists():
            print("Workflow has not been submitted.")
            return
        state = json.loads(STATE.read_text())
        print(json.dumps(state, indent=2))
        ids = ",".join(state["jobs"].values())
        if ids:
            subprocess.run(["sacct", "-X", "-j", ids, "--format=JobID,JobName,Partition,State,ExitCode,Elapsed"])
        return
    if args.action == "start":
        if STATE.exists():
            raise RuntimeError("A workflow already exists. Use 'status' before starting another run.")
        state = {"case": str(ROOT), "cluster": "hydra", "status": "starting", "jobs": {}}
        save(state)
        text = run_step(3, state)
        mesh = re.search(r"Submitted mesh job: (\d+)", text)
        database = re.search(r"Submitted database job: (\d+)", text)
        if not mesh or not database:
            raise RuntimeError("Could not identify the submitted mesh/database jobs.")
        state["jobs"].update(mesh=mesh[1], database=database[1])
        state["status"] = "submitted_mesh_and_database"
        save(state)
        schedule(7, database[1], state)
        return
    if args.stage not in [7, 8, 9, 10]:
        parser.error("advance requires stage 7, 8, 9 or 10")
    state = json.loads(STATE.read_text())
    if args.stage == 10:
        import hashlib
        expected = state.get("rerun_source_sha256")
        if expected:
            for source in [ROOT / "DATA/CMTSOLUTION", ROOT / "WORK/SPECFEM3D/DATA/CMTSOLUTION"]:
                if hashlib.sha256(source.read_bytes()).hexdigest() != expected:
                    state["status"] = "failed_source_consistency"
                    save(state)
                    raise RuntimeError("Source changed during the rerun; refusing mislabeled assembly")
        run_step(10, state)
        run_step(11, state)
        finalize_source_outputs(state)
        state["status"] = "completed"
        save(state)
        print(f"Workflow completed. Results: {state.get('result_directory', str(ROOT / 'OUTPUT_FILES'))}", flush=True)
        return
    text = run_step(args.stage, state)
    match = re.search(r"Submitted (?:InjectedWaves|solver|SPECFEM3D|coupling)[^\n]*job: (\d+)", text, re.I)
    if not match:
        state["status"] = f"failed_submission_step{args.stage}"
        save(state)
        raise RuntimeError(f"Step {args.stage} did not report a submitted job; see its log.")
    state["jobs"][f"step{args.stage}"] = match[1]
    state["status"] = f"submitted_step{args.stage}"
    save(state)
    schedule({7: 8, 8: 9, 9: 10}[args.stage], match[1], state)


if __name__ == "__main__":
    main()
