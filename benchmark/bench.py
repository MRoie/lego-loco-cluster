import argparse
import csv
import os
import subprocess
import time

def run_deploy(replicas):
    env = os.environ.copy()
    env['REPLICAS'] = str(replicas)
    print(f"Starting cluster with {replicas} replicas...")
    try:
        subprocess.run(['./scripts/deploy_single.sh'], check=True, env=env)
    except subprocess.CalledProcessError:
        print('Deployment failed; ensure kubectl and helm are configured')
        return None
    # Placeholder for real measurement hooks
    time.sleep(1)
    return {'replicas': replicas, 'fps': 0, 'bitrate': 0}

def main():
    parser = argparse.ArgumentParser(description='Simple VR benchmark harness')
    parser.add_argument('--replicas', nargs='+', type=int, default=[1,3,9], help='Replica counts to test')
    parser.add_argument('--output', default='results.csv', help='CSV results file')
    args = parser.parse_args()

    results = []
    for r in args.replicas:
        res = run_deploy(r)
        if res:
            results.append(res)
    if results:
        with open(args.output, 'w', newline='') as f:
            writer = csv.DictWriter(f, fieldnames=['replicas', 'fps', 'bitrate'])
            writer.writeheader()
            writer.writerows(results)
        print('Results written to', args.output)

if __name__ == '__main__':
    main()
