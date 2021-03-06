function [results] = testPartDetection(imdb, nnOpts, net, inputs, ~)
% [results] = testDetection(imdb, nnOpts, net, inputs, ~)
%
% Get predicted boxes and scores per class
% Only gets top nnOpts.maxNumBoxesPerImTest boxes (default: 5000)
% Only gets boxes with score higher than nnOpts.minDetectionScore (default: 0.01)
% NMS threshold: nnOpts.nmsTTest (default: 0.3)

% Variables which should probably be in imdb.nnOpts or something
% Jasper: Probably need to do something more robust here
%
% Copyright by Jasper Uijlings, 2015
% Modified by Abel Gonzalez-Garcia, 2016

if isfield(nnOpts, 'maxNumBoxesPerImTest')
    maxNumBoxesPerImTest = nnOpts.maxNumBoxesPerImTest;
else
    maxNumBoxesPerImTest = 5000;
end

if isfield(nnOpts, 'nmsTTest')
    nmsTTest = imdb.nmsTTest;
else
    nmsTTest = 0.3; % non-maximum threshold
end

if isfield(nnOpts, 'minDetectionScore')
    minDetectionScore = nnOpts.minDetectionScore;
else
    minDetectionScore = 0.01;
end

%% Parts

% Get scores
vI = net.getVarIndex('scoresPrt');
scoresStruct = net.vars(vI);
scores = permute(scoresStruct.value, [4 3 2 1]);

% Get boxes
inputNames = inputs(1:2:end);
[~, boxI] = ismember('boxesPrt', inputNames);
boxI = boxI * 2; % Index of actual argument
boxes = inputs{boxI}';


% Get regression targets for boxes
if imdb.boxRegress
    vI = net.getVarIndex('regressionScorePrt');
    regressStruct = net.vars(vI);
    regressFactors = permute(regressStruct.value, [4 3 2 1]);
else
    regressFactors = zeros(size(boxes,1), size(boxes,2) * imdb.numClassesPrt);
end

% Get top boxes for each category. Perform NMS. Thresholds defined at top of function
currMaxBoxes = min(maxNumBoxesPerImTest, size(boxes, 1));
for cI = size(scores,2) : -1 : 1
    % Get top scores and boxes
    [currScoresT, sI] = sort(scores(:,cI), 'descend');
    currScoresT = currScoresT(1:currMaxBoxes);
    sI = sI(1:currMaxBoxes);
    currBoxes = boxes(sI,:);

    % Do regression
    regressFRange = (cI*4)-3:cI*4;
    currRegressF = gather(regressFactors(sI,regressFRange));
    currBoxesReg = BoxRegresssGirshick(currBoxes, currRegressF);
    
    % Get scores (w boxes) above certain threshold
    goodI = currScoresT > minDetectionScore;
    currScoresT = currScoresT(goodI, :);
    currBoxes = currBoxes(goodI, :);
    currBoxesReg = currBoxesReg(goodI, :);

    % Perform NMS
    [~, goodBoxesI] = BoxNMS(currBoxes, nmsTTest);
    currBoxes = currBoxes(goodBoxesI, :);
    currScores = currScoresT(goodBoxesI ,:);
    
    results.boxesPrt{cI} = gather(currBoxes);
    results.scoresPrt{cI} = gather(currScores);
    
    if imdb.boxRegress
        [~, goodBoxesI] = BoxNMS(currBoxesReg, nmsTTest);
        currBoxesReg = currBoxesReg(goodBoxesI, :);
        currScoresRegressed = currScoresT(goodBoxesI, :);
        results.boxesRegressedPrt{cI} = gather(currBoxesReg);
        results.scoresRegressedPrt{cI} = gather(currScoresRegressed);
    end
end



%% Objects

% Get scores
vI = net.getVarIndex('scoresObj');
scoresStruct = net.vars(vI);
scores = permute(scoresStruct.value, [4 3 2 1]);

% Get boxes
inputNames = inputs(1:2:end);
[~, boxI] = ismember('boxesObj', inputNames);
boxI = boxI * 2; % Index of actual argument
boxes = inputs{boxI}';


% Get regression targets for boxes
if imdb.boxRegress
    vI = net.getVarIndex('regressionScoreObj');
    regressStruct = net.vars(vI);
    regressFactors = permute(regressStruct.value, [4 3 2 1]);
else
    regressFactors = zeros(size(boxes,1), size(boxes,2) * imdb.numClasses);
end

% Get top boxes for each category. Perform NMS. Thresholds defined at top of function
currMaxBoxes = min(maxNumBoxesPerImTest, size(boxes, 1));

for cI = size(scores,2) : -1 : 1
    % Get top scores and boxes
    [currScoresT, sI] = sort(scores(:,cI), 'descend');
    currScoresT = currScoresT(1:currMaxBoxes);
    sI = sI(1:currMaxBoxes);
    currBoxes = boxes(sI,:);

    % Do regression
    regressFRange = (cI*4)-3:cI*4;
    currRegressF = gather(regressFactors(sI,regressFRange));
    currBoxesReg = BoxRegresssGirshick(currBoxes, currRegressF);
    
    % Get scores (w boxes) above certain threshold
    goodI = currScoresT > minDetectionScore;
    currScoresT = currScoresT(goodI, :);
    currBoxes = currBoxes(goodI, :);
    currBoxesReg = currBoxesReg(goodI, :);

    % Perform NMS
    [~, goodBoxesI] = BoxNMS(currBoxes, nmsTTest);
    currBoxes = currBoxes(goodBoxesI, :);
    currScores = currScoresT(goodBoxesI ,:);
    
    results.boxesObj{cI} = gather(currBoxes);
    results.scoresObj{cI} = gather(currScores);
    
    if imdb.boxRegress
        [~, goodBoxesI] = BoxNMS(currBoxesReg, nmsTTest);
        currBoxesReg = currBoxesReg(goodBoxesI, :);
        currScoresRegressed = currScoresT(goodBoxesI, :);
        results.boxesRegressedObj{cI} = gather(currBoxesReg);
        results.scoresRegressedObj{cI} = gather(currScoresRegressed);
    end
end