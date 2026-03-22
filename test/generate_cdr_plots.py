import pandas as pd
import plotly.graph_objects as go
import plotly.express as px
import os

def create_cdr_report():
    df = pd.read_csv('sweep_results.csv')
    
    # Exclude Lorenz for the main bit-width comparison since it's structurally different
    df_main = df[df['Module'] != 'cond_lorenz']
    
    # 1. Entropy vs Width Plot
    fig1 = px.line(df_main, x='Width', y='Entropy', color='Module', markers=True,
                   title='Shannon Entropy vs. Bit-Width',
                   labels={'Width': 'Register Width (Bits)', 'Entropy': 'Shannon Entropy (Bits/Bit)'})
    fig1.update_yaxes(range=[0.99, 1.001])
    fig1.write_html("cdr_entropy_vs_width.html")

    # 2. P-Value (Uniformity) vs Width Plot
    fig2 = px.line(df_main, x='Width', y='P-Value', color='Module', markers=True,
                   title='Chi-Square P-Value (Uniformity) vs. Bit-Width',
                   labels={'Width': 'Register Width (Bits)', 'P-Value': 'P-Value (>0.05 is Uniform)'})
    fig2.add_hline(y=0.05, line_dash="dash", line_color="red", annotation_text="Significance Threshold (0.05)")
    fig2.write_html("cdr_uniformity_vs_width.html")

if __name__ == "__main__":
    create_cdr_report()
    print("CDR plots generated.")
