%% Leonardo Campus RF Coverage Planning Case Study
% MATLAB R2019b-compatible quantitative comparative model.
%
% PURPOSE
% -------
% This script complements the original 3-D urban ray-tracing visualization
% with a reproducible quantitative scenario comparison that runs in R2019b.
%
% It does NOT claim certified coverage accuracy. Public OpenCellID-derived
% transmitter coordinates are used, while frequency, power, antenna gain
% and path-loss exponent are explicit modelling assumptions.
%
% The decision metric is deliberately RELATIVE:
%   - the baseline lower-tail region is defined as the weakest 10% of the
%     baseline predicted-power grid;
%   - alternatives are chosen to improve the principal lower-tail zone;
%   - the same fixed baseline P10 threshold is then used for all scenarios.
%
% Run from repository root:
%   leonardo_coverage_case_study

clear; clc; close all;

%% 1. CONFIGURATION
cfg.campusLat = 45.4781;
cfg.campusLon = 9.2297;

% Public-data selection
cfg.radioTechnology = 'LTE';

% Modelling assumptions
cfg.frequency_Hz = 1800e6;
cfg.txPower_W = 10;
cfg.txPower_dBm = 10*log10(cfg.txPower_W*1000);
cfg.antennaHeight_m = 25;      % documented assumption, not explicit in model
cfg.receiverHeight_m = 1.5;    % documented assumption, not explicit in model
cfg.antennaGain_dBi = 0;
cfg.pathLossExponent = 3.5;
cfg.referenceDistance_m = 1;

% Study grid
cfg.studyRadius_m = 600;
cfg.gridResolution_m = 15;

% Relative planning metric
cfg.lowerTailPercentile = 10;

% Alternatives
cfg.relocationDistance_m = 80;

% Output
cfg.outputDir = fullfile(pwd,'outputs');
if ~exist(cfg.outputDir,'dir')
    mkdir(cfg.outputDir);
end

fprintf('\nLeonardo Campus RF coverage-planning case study\n');
fprintf('MATLAB %s\n',version);
fprintf('Quantitative model: comparative log-distance screening model\n');
fprintf('LTE layer: %.0f MHz | assumed TX power: %.1f dBm\n', ...
    cfg.frequency_Hz/1e6,cfg.txPower_dBm);
fprintf('Study radius: %d m | resolution: %d m\n\n', ...
    cfg.studyRadius_m,cfg.gridResolution_m);

%% 2. LOAD AND VALIDATE TRANSMITTER DATA
candidateFiles = { ...
    fullfile(pwd,'data','Milan_towers.csv'), ...
    fullfile(pwd,'map','Milan_towers.csv'), ...
    fullfile(pwd,'Milan_towers.csv')};

dataFile = '';
for k = 1:numel(candidateFiles)
    if exist(candidateFiles{k},'file')
        dataFile = candidateFiles{k};
        break;
    end
end

if isempty(dataFile)
    error(['Milan_towers.csv not found. Place it in data/, map/, ' ...
           'or the repository root.']);
end

towers = readtable(dataFile);

requiredVars = {'lat','lon'};
for k = 1:numel(requiredVars)
    if ~ismember(requiredVars{k},towers.Properties.VariableNames)
        error('Input CSV must contain column "%s".',requiredVars{k});
    end
end

valid = isfinite(towers.lat) & isfinite(towers.lon) & ...
        towers.lat >= -90 & towers.lat <= 90 & ...
        towers.lon >= -180 & towers.lon <= 180;
towers = towers(valid,:);

if ismember('radio',towers.Properties.VariableNames)
    radioText = cellstr(string(towers.radio));
    towers = towers(strcmpi(strtrim(radioText),cfg.radioTechnology),:);
end

if isempty(towers)
    error('No valid %s records remain after filtering.',cfg.radioTechnology);
end

%% 3. FILTER TO 600 m STUDY AREA
[txEast_m,txNorth_m] = latLonToLocal( ...
    towers.lat,towers.lon,cfg.campusLat,cfg.campusLon);

keep = hypot(txEast_m,txNorth_m) <= cfg.studyRadius_m;
towers = towers(keep,:);
txEast_m = txEast_m(keep);
txNorth_m = txNorth_m(keep);

if isempty(towers)
    error('No transmitters found inside the study area.');
end

fprintf('Using %d public-data LTE coordinates inside the study area.\n', ...
    height(towers));

%% 4. BUILD GRID
axisVec = -cfg.studyRadius_m:cfg.gridResolution_m:cfg.studyRadius_m;
[xGrid_m,yGrid_m] = meshgrid(axisVec,axisVec);
studyMask = hypot(xGrid_m,yGrid_m) <= cfg.studyRadius_m;

[latGrid,lonGrid] = localToLatLon( ...
    xGrid_m,yGrid_m,cfg.campusLat,cfg.campusLon);

%% 5. BASELINE
baselinePower_dBm = bestServerPower( ...
    xGrid_m,yGrid_m,studyMask,txEast_m,txNorth_m, ...
    cfg.txPower_dBm,cfg.antennaGain_dBi,cfg.frequency_Hz, ...
    cfg.pathLossExponent,cfg.referenceDistance_m);

baselineVals = baselinePower_dBm(studyMask & isfinite(baselinePower_dBm));

% FIXED cross-scenario decision threshold:
% weakest 10% boundary of the BASELINE only.
baselineTailThreshold_dBm = prctile( ...
    baselineVals,cfg.lowerTailPercentile);

baselineLowerTailMask = studyMask & ...
    baselinePower_dBm <= baselineTailThreshold_dBm;

baseline = computeKpis('Baseline',baselinePower_dBm,studyMask, ...
    baselineTailThreshold_dBm,cfg);

fprintf('Baseline P10 threshold: %.2f dBm\n',baselineTailThreshold_dBm);

%% 6. PRINCIPAL BASELINE LOWER-TAIL ZONE
zoneTable = buildWeakZoneTable( ...
    baselineLowerTailMask,baselinePower_dBm,xGrid_m,yGrid_m, ...
    latGrid,lonGrid,cfg);

if isempty(zoneTable)
    error('Unable to identify the baseline lower-tail region.');
end

targetX_m = zoneTable.CentroidEast_m(1);
targetY_m = zoneTable.CentroidNorth_m(1);

%% 7. ALTERNATIVE 1 — RELOCATE NEAREST EXISTING SITE
distToTarget = hypot(txEast_m-targetX_m,txNorth_m-targetY_m);
[~,moveIdx] = min(distToTarget);

relocatedEast_m = txEast_m;
relocatedNorth_m = txNorth_m;

dx = targetX_m - txEast_m(moveIdx);
dy = targetY_m - txNorth_m(moveIdx);
sourceToTarget_m = hypot(dx,dy);

if sourceToTarget_m > 0
    actualMove_m = min(cfg.relocationDistance_m,sourceToTarget_m);
    relocatedEast_m(moveIdx) = txEast_m(moveIdx) + ...
        actualMove_m*dx/sourceToTarget_m;
    relocatedNorth_m(moveIdx) = txNorth_m(moveIdx) + ...
        actualMove_m*dy/sourceToTarget_m;
else
    actualMove_m = 0;
end

relocatedPower_dBm = bestServerPower( ...
    xGrid_m,yGrid_m,studyMask,relocatedEast_m,relocatedNorth_m, ...
    cfg.txPower_dBm,cfg.antennaGain_dBi,cfg.frequency_Hz, ...
    cfg.pathLossExponent,cfg.referenceDistance_m);

relocated = computeKpis( ...
    'Relocate selected site',relocatedPower_dBm,studyMask, ...
    baselineTailThreshold_dBm,cfg);

%% 8. ALTERNATIVE 2 — ADD CANDIDATE SITE AT PRINCIPAL LOWER-TAIL CENTROID
candidateEast_m = targetX_m;
candidateNorth_m = targetY_m;

addedEast_m = [txEast_m; candidateEast_m];
addedNorth_m = [txNorth_m; candidateNorth_m];

addedPower_dBm = bestServerPower( ...
    xGrid_m,yGrid_m,studyMask,addedEast_m,addedNorth_m, ...
    cfg.txPower_dBm,cfg.antennaGain_dBi,cfg.frequency_Hz, ...
    cfg.pathLossExponent,cfg.referenceDistance_m);

added = computeKpis( ...
    'Add candidate site',addedPower_dBm,studyMask, ...
    baselineTailThreshold_dBm,cfg);

%% 9. QUANTITATIVE COMPARISON
scenarioNames = {baseline.Name; relocated.Name; added.Name};

medianPower_dBm = [baseline.MedianPower_dBm; ...
                   relocated.MedianPower_dBm; ...
                   added.MedianPower_dBm];

p10Power_dBm = [baseline.P10Power_dBm; ...
                relocated.P10Power_dBm; ...
                added.P10Power_dBm];

p5Power_dBm = [baseline.P5Power_dBm; ...
               relocated.P5Power_dBm; ...
               added.P5Power_dBm];

minimumPower_dBm = [baseline.MinPower_dBm; ...
                    relocated.MinPower_dBm; ...
                    added.MinPower_dBm];

areaBelowBaselineP10_pct = [baseline.AreaBelowFixedThreshold_pct; ...
                            relocated.AreaBelowFixedThreshold_pct; ...
                            added.AreaBelowFixedThreshold_pct];

areaBelowBaselineP10_m2 = [baseline.AreaBelowFixedThreshold_m2; ...
                           relocated.AreaBelowFixedThreshold_m2; ...
                           added.AreaBelowFixedThreshold_m2];

p10Improvement_dB = p10Power_dBm - p10Power_dBm(1);
p5Improvement_dB = p5Power_dBm - p5Power_dBm(1);
minimumImprovement_dB = minimumPower_dBm - minimumPower_dBm(1);

tradeoff = { ...
    'Existing assumed configuration'; ...
    'Requires relocation feasibility / civil changes'; ...
    'Requires new site, power, backhaul and permitting'};

kpiTable = table( ...
    scenarioNames,medianPower_dBm,p10Power_dBm,p5Power_dBm, ...
    minimumPower_dBm,areaBelowBaselineP10_pct, ...
    areaBelowBaselineP10_m2,p10Improvement_dB,p5Improvement_dB, ...
    minimumImprovement_dB,tradeoff, ...
    'VariableNames',{ ...
    'Scenario','MedianPower_dBm','P10Power_dBm','P5Power_dBm', ...
    'MinimumPower_dBm','AreaBelowBaselineP10_pct', ...
    'AreaBelowBaselineP10_m2','P10Improvement_dB', ...
    'P5Improvement_dB','MinimumImprovement_dB','Tradeoff'});

% Technical performance recommendation:
% prioritize lower-tail robustness rather than median power.
technicalScore = p10Power_dBm + 0.5*p5Power_dBm;
[~,recommendedIdx] = max(technicalScore);
recommendedScenario = scenarioNames{recommendedIdx};

fprintf('\nScenario KPI comparison:\n');
disp(kpiTable);
fprintf('Technical performance leader: %s\n',recommendedScenario);

writetable(kpiTable,fullfile(cfg.outputDir,'scenario_kpis.csv'));
writetable(zoneTable,fullfile(cfg.outputDir,'baseline_lower_tail_zones.csv'));

%% 10. EXPORT SCENARIO LOCATIONS
[relocatedLat,relocatedLon] = localToLatLon( ...
    relocatedEast_m(moveIdx),relocatedNorth_m(moveIdx), ...
    cfg.campusLat,cfg.campusLon);

[candidateLat,candidateLon] = localToLatLon( ...
    candidateEast_m,candidateNorth_m,cfg.campusLat,cfg.campusLon);

scenarioLocations = table( ...
    moveIdx,actualMove_m,relocatedLat,relocatedLon, ...
    candidateLat,candidateLon, ...
    'VariableNames',{ ...
    'RelocatedSourceRow','RelocationDistance_m', ...
    'RelocatedLatitude','RelocatedLongitude', ...
    'CandidateLatitude','CandidateLongitude'});

writetable(scenarioLocations, ...
    fullfile(cfg.outputDir,'scenario_locations.csv'));

txExport = towers;
txExport.AssumedFrequency_MHz = repmat( ...
    cfg.frequency_Hz/1e6,height(towers),1);
txExport.AssumedTxPower_dBm = repmat( ...
    cfg.txPower_dBm,height(towers),1);
txExport.AssumedAntennaHeight_m = repmat( ...
    cfg.antennaHeight_m,height(towers),1);

writetable(txExport,fullfile(cfg.outputDir,'transmitters_used.csv'));

%% 11. VISUAL SETTINGS
allScenarioValues = [baselinePower_dBm(studyMask); ...
                     relocatedPower_dBm(studyMask); ...
                     addedPower_dBm(studyMask)];

coverageLow = floor(prctile(allScenarioValues,1)/5)*5;
coverageHigh = ceil(prctile(allScenarioValues,99)/5)*5;
coverageLimits = [coverageLow coverageHigh];

deltaRelocated = relocatedPower_dBm-baselinePower_dBm;
deltaAdded = addedPower_dBm-baselinePower_dBm;
deltaVals = [deltaRelocated(studyMask); deltaAdded(studyMask)];
deltaLimit = max(2,ceil(prctile(abs(deltaVals),99)));

%% 12. FIGURES

% 01 — Study area
figure('Color','w','Position',[100 100 900 720]);
hold on;
th = linspace(0,2*pi,400);
plot(cfg.studyRadius_m*cos(th),cfg.studyRadius_m*sin(th), ...
    'k--','LineWidth',1.3);
scatter(txEast_m,txNorth_m,60,'^','filled');
plot(0,0,'kp','MarkerSize',14,'MarkerFaceColor','w');
axis equal; grid on;
xlim([-650 650]); ylim([-650 650]);
xlabel('East of campus centre (m)');
ylabel('North of campus centre (m)');
title('Leonardo Campus Study Area and LTE Coordinates');
legend('Study boundary','Public-data LTE coordinate','Campus centre', ...
    'Location','best');
savePng(gcf,fullfile(cfg.outputDir,'01_study_area_transmitters.png'));

% 02 — Baseline predicted power
plotCoverage(xGrid_m,yGrid_m,baselinePower_dBm,studyMask, ...
    txEast_m,txNorth_m,coverageLimits, ...
    'Baseline Comparative Received-Power Model');
hold on;
contour(xGrid_m,yGrid_m,baselinePower_dBm, ...
    [baselineTailThreshold_dBm baselineTailThreshold_dBm], ...
    'k--','LineWidth',1.5);
savePng(gcf,fullfile(cfg.outputDir,'02_baseline_coverage.png'));

% 03 — Baseline lower-tail region
figure('Color','w','Position',[100 100 900 720]);
contourf(xGrid_m,yGrid_m,double(baselineLowerTailMask), ...
    [-0.5 0.5 1.5],'LineStyle','none');
axis equal tight; hold on;
scatter(txEast_m,txNorth_m,55,'^','filled');
plot(targetX_m,targetY_m,'rx','MarkerSize',14,'LineWidth',2.5);
xlabel('East of campus centre (m)');
ylabel('North of campus centre (m)');
title(sprintf('Baseline Lower-Tail Region: Weakest %d%%', ...
    cfg.lowerTailPercentile));
legend('LTE coordinates','Principal lower-tail centroid', ...
    'Location','best');
savePng(gcf,fullfile(cfg.outputDir,'03_baseline_lower_tail_region.png'));

% 04 — Relocation
plotCoverage(xGrid_m,yGrid_m,relocatedPower_dBm,studyMask, ...
    relocatedEast_m,relocatedNorth_m,coverageLimits, ...
    'Alternative 1 — Relocate Existing Site');
hold on;
plot(relocatedEast_m(moveIdx),relocatedNorth_m(moveIdx), ...
    'ro','MarkerSize',12,'LineWidth',2);
savePng(gcf,fullfile(cfg.outputDir,'04_alternative_relocation.png'));

% 05 — Added site
plotCoverage(xGrid_m,yGrid_m,addedPower_dBm,studyMask, ...
    addedEast_m,addedNorth_m,coverageLimits, ...
    'Alternative 2 — Add Candidate Site');
hold on;
plot(candidateEast_m,candidateNorth_m, ...
    'ro','MarkerSize',12,'LineWidth',2);
savePng(gcf,fullfile(cfg.outputDir,'05_alternative_added_site.png'));

% 06 — Side-by-side comparison
figure('Color','w','Position',[60 100 1500 470]);
maps = {baselinePower_dBm,relocatedPower_dBm,addedPower_dBm};
names = {'Baseline','Relocate selected site','Add candidate site'};
for i = 1:3
    subplot(1,3,i);
    Z = maps{i}; Z(~studyMask)=NaN;
    imagesc(axisVec,axisVec,Z);
    set(gca,'YDir','normal');
    axis equal tight; caxis(coverageLimits);
    title(names{i});
    xlabel('East (m)'); ylabel('North (m)');
    cb = colorbar;
    ylabel(cb,'Predicted power (dBm)');
end
savePng(gcf,fullfile(cfg.outputDir,'06_scenario_comparison.png'));

% 07 — Improvement maps
figure('Color','w','Position',[80 100 1250 520]);

subplot(1,2,1);
D = deltaRelocated; D(~studyMask)=NaN;
imagesc(axisVec,axisVec,D);
set(gca,'YDir','normal');
axis equal tight;
caxis([-deltaLimit deltaLimit]);
colorbar;
title('Relocation: Change vs Baseline (dB)');
xlabel('East (m)'); ylabel('North (m)');

subplot(1,2,2);
D = deltaAdded; D(~studyMask)=NaN;
imagesc(axisVec,axisVec,D);
set(gca,'YDir','normal');
axis equal tight;
caxis([-deltaLimit deltaLimit]);
colorbar;
title('Added Site: Change vs Baseline (dB)');
xlabel('East (m)'); ylabel('North (m)');

savePng(gcf,fullfile(cfg.outputDir,'07_improvement_maps.png'));

% 08 — Lower-tail KPI comparison
figure('Color','w','Position',[100 100 920 620]);
Y = [p10Improvement_dB p5Improvement_dB minimumImprovement_dB];
bar(categorical(scenarioNames),Y);
grid on;
ylabel('Improvement relative to baseline (dB)');
title('Lower-Tail Robustness Improvement');
legend('P10','P5','Minimum','Location','best');
savePng(gcf,fullfile(cfg.outputDir,'08_lower_tail_kpi_comparison.png'));

% 09 — Area remaining below the baseline P10 boundary
figure('Color','w','Position',[100 100 900 620]);
bar(categorical(scenarioNames),areaBelowBaselineP10_pct);
grid on;
ylabel(sprintf('Area below baseline P10 = %.2f dBm (%%)', ...
    baselineTailThreshold_dBm));
title('Reduction of the Baseline Lower-Tail Region');
savePng(gcf,fullfile(cfg.outputDir,'09_lower_tail_area_comparison.png'));

% 10 — Received-power CDF
figure('Color','w','Position',[100 100 920 620]); hold on;
plotEmpiricalCdf(baselinePower_dBm(studyMask),'LineWidth',1.7);
plotEmpiricalCdf(relocatedPower_dBm(studyMask),'LineWidth',1.7);
plotEmpiricalCdf(addedPower_dBm(studyMask),'LineWidth',1.7);
yl = ylim;
plot([baselineTailThreshold_dBm baselineTailThreshold_dBm], ...
    yl,'k--','LineWidth',1.2);
ylim(yl);
grid on;
xlabel('Comparative predicted received power (dBm)');
ylabel('Empirical CDF');
title('Received-Power Distribution — Lower Tail is the Decision Focus');
legend('Baseline','Relocate selected site','Add candidate site', ...
    'Baseline P10 boundary','Location','best');
savePng(gcf,fullfile(cfg.outputDir,'10_received_power_cdf.png'));

% 11 — Recommended configuration
switch recommendedIdx
    case 1
        recPower = baselinePower_dBm;
        recX = txEast_m; recY = txNorth_m;
    case 2
        recPower = relocatedPower_dBm;
        recX = relocatedEast_m; recY = relocatedNorth_m;
    otherwise
        recPower = addedPower_dBm;
        recX = addedEast_m; recY = addedNorth_m;
end

plotCoverage(xGrid_m,yGrid_m,recPower,studyMask, ...
    recX,recY,coverageLimits, ...
    ['Technical Performance Leader — ' recommendedScenario]);

savePng(gcf,fullfile(cfg.outputDir,'11_recommended_configuration.png'));

%% 13. SAVE RESULT STRUCT
results.cfg = cfg;
results.baselineTailThreshold_dBm = baselineTailThreshold_dBm;
results.kpiTable = kpiTable;
results.zoneTable = zoneTable;
results.recommendedScenario = recommendedScenario;
results.relocatedSourceRow = moveIdx;
results.relocationDistance_m = actualMove_m;
results.candidateLatitude = candidateLat;
results.candidateLongitude = candidateLon;

save(fullfile(cfg.outputDir,'case_study_results.mat'),'results');

fprintf('\nFinished.\n');
fprintf('Baseline P10 boundary: %.2f dBm\n',baselineTailThreshold_dBm);
fprintf('Technical performance leader: %s\n',recommendedScenario);
fprintf('Outputs: %s\n',cfg.outputDir);
fprintf(['Interpretation: relative planning comparison only; ' ...
         'not calibrated field coverage.\n']);

%% LOCAL FUNCTIONS

function [east_m,north_m] = latLonToLocal(lat,lon,lat0,lon0)
R = 6371000;
north_m = deg2rad(lat-lat0)*R;
east_m = deg2rad(lon-lon0)*R*cos(deg2rad(lat0));
end

function [lat,lon] = localToLatLon(east_m,north_m,lat0,lon0)
R = 6371000;
lat = lat0 + rad2deg(north_m/R);
lon = lon0 + rad2deg(east_m/(R*cos(deg2rad(lat0))));
end

function power_dBm = bestServerPower(xGrid,yGrid,mask,txX,txY, ...
    txPower_dBm,antennaGain_dBi,frequency_Hz,n,d0_m)

c = 299792458;
lambda = c/frequency_Hz;
plD0_dB = 20*log10(4*pi*d0_m/lambda);

power_dBm = -inf(size(xGrid));

for i = 1:numel(txX)
    d = hypot(xGrid-txX(i),yGrid-txY(i));
    d = max(d,d0_m);
    pathLoss_dB = plD0_dB + 10*n*log10(d/d0_m);
    p = txPower_dBm + antennaGain_dBi - pathLoss_dB;
    power_dBm = max(power_dBm,p);
end

power_dBm(~mask) = NaN;
end

function k = computeKpis(name,power_dBm,mask,fixedThreshold_dBm,cfg)

vals = power_dBm(mask & isfinite(power_dBm));
cellArea_m2 = cfg.gridResolution_m^2;

k.Name = name;
k.MedianPower_dBm = median(vals);
k.P10Power_dBm = prctile(vals,10);
k.P5Power_dBm = prctile(vals,5);
k.MinPower_dBm = min(vals);

below = vals <= fixedThreshold_dBm;
k.AreaBelowFixedThreshold_pct = 100*mean(below);
k.AreaBelowFixedThreshold_m2 = sum(below)*cellArea_m2;
end

function zoneTable = buildWeakZoneTable(mask,power_dBm,xGrid,yGrid, ...
    latGrid,lonGrid,cfg)

if exist('bwconncomp','file') ~= 2 || ~any(mask(:))
    error(['Image Processing Toolbox is required for connected-zone ' ...
           'analysis in this version.']);
end

CC = bwconncomp(mask,8);
stats = regionprops(CC,'Area','PixelIdxList');

areas_m2 = [stats.Area]'*cfg.gridResolution_m^2;
[areas_m2,order] = sort(areas_m2,'descend');

nZones = min(numel(order),10);

ZoneRank = (1:nZones)';
Area_m2 = zeros(nZones,1);
CentroidEast_m = zeros(nZones,1);
CentroidNorth_m = zeros(nZones,1);
CentroidLatitude = zeros(nZones,1);
CentroidLongitude = zeros(nZones,1);
MinimumPower_dBm = zeros(nZones,1);

for z = 1:nZones
    idx = stats(order(z)).PixelIdxList;
    Area_m2(z) = areas_m2(z);
    CentroidEast_m(z) = mean(xGrid(idx));
    CentroidNorth_m(z) = mean(yGrid(idx));
    CentroidLatitude(z) = mean(latGrid(idx));
    CentroidLongitude(z) = mean(lonGrid(idx));
    MinimumPower_dBm(z) = min(power_dBm(idx));
end

zoneTable = table( ...
    ZoneRank,Area_m2,CentroidEast_m,CentroidNorth_m, ...
    CentroidLatitude,CentroidLongitude,MinimumPower_dBm);
end

function plotCoverage(xGrid,yGrid,power_dBm,mask,txX,txY,limits,titleText)
figure('Color','w','Position',[100 100 900 720]);
Z = power_dBm;
Z(~mask)=NaN;
imagesc(xGrid(1,:),yGrid(:,1),Z);
set(gca,'YDir','normal');
axis equal tight;
caxis(limits);
hold on;
scatter(txX,txY,48,'^','filled');
cb = colorbar;
ylabel(cb,'Comparative predicted power (dBm)');
xlabel('East of campus centre (m)');
ylabel('North of campus centre (m)');
title(titleText);
end

function plotEmpiricalCdf(values,varargin)
values = sort(values(isfinite(values)));
cdfVals = (1:numel(values))/numel(values);
plot(values,cdfVals,varargin{:});
end

function savePng(figHandle,fileName)
set(figHandle,'PaperPositionMode','auto');
print(figHandle,fileName,'-dpng','-r220');
end
