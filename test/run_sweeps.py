import subprocess
import os
import pandas as pd

def run_test(dut, width):
    print(f">>> Running {dut} with WIDTH={width}...")
    env = os.environ.copy()
    env["UNIT"] = "1"
    env["DUT_NAME"] = dut
    env["WIDTH"] = str(width)
    
    try:
        # Run make
        cmd = ["make", "clean", "sim"]
        result = subprocess.run(cmd, env=env, cwd=".", 
                                capture_output=True, text=True, timeout=120)
        
        # Parse output for Entropy and p-val
        entropy = 0
        pval = 0
        for line in result.stdout.split('\n'):
            if "Results: Entropy=" in line:
                parts = line.split('=')
                entropy = float(parts[1].split(',')[0])
                pval = float(parts[2])
        
        return {"Module": dut, "Width": width, "Entropy": entropy, "P-Value": pval, "Status": "PASS" if result.returncode == 0 else "FAIL"}
    except Exception as e:
        return {"Module": dut, "Width": width, "Entropy": 0, "P-Value": 0, "Status": f"ERROR: {str(e)}"}

if __name__ == "__main__":
    modules = ["cond_tent_map", "cond_bernoulli", "cond_logistic", "cond_coupled_tent", "cond_lorenz", "cond_lfsr"]
    widths = [8, 12, 16, 24, 32]
    
    results = []
    
    for m in modules:
        for w in widths:
            # Skip widths not suitable for some modules if needed
            if m == "cond_lorenz" and w < 16: continue # Lorenz needs at least 16 for stability
            res = run_test(m, w)
            results.append(res)
            
    df = pd.DataFrame(results)
    print("\n" + "="*60)
    print("CHAOTIC CONDITIONER SWEEP RESULTS")
    print("="*60)
    print(df.to_string(index=False))
    df.to_csv("sweep_results.csv")
    print("\nSummary saved to sweep_results.csv")
