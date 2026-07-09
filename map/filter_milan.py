import pandas as pd

columns = [
    "radio", "mcc", "net", "area", "cell", "unit",
    "lon", "lat", "range", "samples", "changeable",
    "created", "updated", "averageSignal"
]

df = pd.read_csv("Italy_towers.csv", names=columns, header=0, low_memory=False)
print(f"Total rows loaded: {len(df)}")

# Step 1: correct country
italy_only = df[df["mcc"] == 222]
print(f"After MCC=222 (Italy only):       {len(italy_only)}")

# Step 2: drop rows with missing/invalid coordinates
valid_coords = italy_only[
    italy_only["lat"].notna() & italy_only["lon"].notna() &
    (italy_only["lat"] != 0) & (italy_only["lon"] != 0) &
    (italy_only["lat"].between(-90, 90)) &
    (italy_only["lon"].between(-180, 180))
]
print(f"After removing invalid coords:     {len(valid_coords)}")

# Step 3: bounding box + 500m padding
min_lat = 45.4686500
max_lat = 45.4836900
min_lon = 9.2178700
max_lon = 9.2383400

padding_lat = 0.0045
padding_lon = 0.0063

in_bbox = valid_coords[
    (valid_coords["lat"] >= min_lat - padding_lat) &
    (valid_coords["lat"] <= max_lat + padding_lat) &
    (valid_coords["lon"] >= min_lon - padding_lon) &
    (valid_coords["lon"] <= max_lon + padding_lon)
]
print(f"After Milan bounding box + 500m:   {len(in_bbox)}")

# Step 4: minimum sample count
clean = in_bbox[in_bbox["samples"] > 3]
print(f"After samples > 3:                 {len(clean)}")

# Step 5: only 3G/4G/5G
modern = clean[clean["radio"].isin(["UMTS", "LTE", "NR"])]
print(f"After keeping only 3G/4G/5G:       {len(modern)}")

print(f"\nBreakdown by radio technology:")
print(modern["radio"].value_counts())

print(f"\nBreakdown by operator (MNC):")
mnc_map = {1: "TIM", 10: "Vodafone", 88: "WindTre", 99: "WindTre", 50: "Iliad"}
print(modern["net"].map(mnc_map).value_counts())

modern.to_csv("Milan_towers.csv", index=False)
print(f"\nSaved Milan_towers.csv with {len(modern)} towers")