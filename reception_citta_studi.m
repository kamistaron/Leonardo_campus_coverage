clear; clc; close all;

%% 1. Open 3D viewer with Milan buildings
viewer = siteviewer("Buildings", "map.osm", "Basemap", "openstreetmap");

%% 2. Define campus center and coverage range
campusLat = 45.4781;   % Politecnico di Milano, Leonardo campus
campusLon = 9.2297;
maxRange  = 600;       % meters — adjust if campus is larger/smaller than this

%% 3. Load antennas from CSV and filter by real distance to campus
towers = readtable("Milan_towers.csv");

% Haversine-ish flat-earth approximation (fine for distances under a few km)
R = 6371000; % Earth radius in meters
dLat = deg2rad(towers.lat - campusLat);
dLon = deg2rad(towers.lon - campusLon);
a = sin(dLat/2).^2 + cos(deg2rad(campusLat)) .* cos(deg2rad(towers.lat)) .* sin(dLon/2).^2;
c = 2 * atan2(sqrt(a), sqrt(1-a));
distToCampus = R .* c;  % meters

towers = towers(distToCampus <= maxRange, :);
fprintf("Filtered to %d towers within %d m of campus.\n", height(towers), maxRange);

% Map radio type to frequency (Hz)
freq_map = containers.Map({'UMTS','LTE','NR'}, ...
    {2100e6, 1800e6, 3500e6});

%% 4. Build txsite array
fprintf("Building tx sites from %d towers...\n", height(towers));
txArray = txsite.empty;
for i = 1:height(towers)
    radio = string(towers.radio(i));
    if ~isKey(freq_map, radio)
        continue;
    end
    freq = freq_map(radio);
    txArray(end+1) = txsite( ...
        "Latitude",              towers.lat(i), ...
        "Longitude",             towers.lon(i), ...
        "AntennaHeight",         25, ...
        "TransmitterFrequency",  freq, ...
        "TransmitterPower",      10, ...
        "Name",                  radio + " " + i);
end
fprintf("Loaded %d tx sites.\n", length(txArray));

show(txArray, "Map", viewer, "ShowAntennaHeight", false);

%% 5. Coverage map
pmSBR = propagationModel("raytracing", Method="sbr", MaxNumReflections=2);

coverage(txArray, pmSBR, ...
    SignalStrengths = -100:-5, ...
    MaxRange         = maxRange, ...
    Resolution       = 5, ...      
    Map              = viewer);