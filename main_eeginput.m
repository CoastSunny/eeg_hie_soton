clear all
close all

subjects = {'2.1.1', '2.4.2', '2.5.1', '2.5.2', '2.2.1', '2.2.2', '2.3.2'};

N = size(subjects,2);
m = 900;

epochs = zeros(1, size(subjects,2));
if exist('features.mat', 'file')
    load features.mat
else
    for i = 1:size(subjects,2)
        sub = cell2mat(subjects(i));
        dotlessSub = ['sub' regexprep(sub, {'\.'},{''})];
        [features.(dotlessSub).data, features.(dotlessSub).index,...
            epochs(i)] = eeg_hie_feaX(...
            ['H:\repos\eeg_hie_soton\RAWEEGDATA\' sub ' 1min']);
    end
    display('All subjects were successfully analysed.');
    name = 'features.mat';
    save(name,'features');
end

X = zeros(m,N);
for i = 1:N
    sub = cell2mat(subjects(i));
    dotlessSub = ['sub' regexprep(sub, {'\.'},{''})];
    X(:,i) = features.(dotlessSub).data;
end

N1 = 1:4;
N2 = 5:7;
X1 = zscore(X(:,N1), [], 1);
X2 = zscore(X(:,N2), [], 1);

FDR = ((mean(X1,2) - mean(X2,2)).^2) ./...
    ((var(X1,0,2).^2) + (var(X2,0,2).^2));

indexFeatures = features.sub211.index';
[~, inFDRALL] = sort(FDR,'descend');

topFEA = inFDRALL(1:7);
[hE5, pE] = ttest2(X1, X2, 'Vartype', 'equal', 'Dim', 2);
[hE1, ~] = ttest2(X1, X2, 'Vartype', 'equal', 'Dim', 2, 'Alpha', 0.01);
[hU5, pU] = ttest2(X1, X2, 'Vartype', 'unequal', 'Dim', 2);
[hU1, ~] = ttest2(X1, X2, 'Vartype', 'unequal', 'Dim', 2, 'Alpha', 0.01);
pWW = zeros(900,1);
for i = 1:900
    pWW(i) = ranksum(X1(i,:),X2(i,:));
end
hWW5 = pWW < 0.05;
hWW1 = pWW < 0.01;
sortedFeatures = table(indexFeatures(topFEA), FDR(topFEA), pE(topFEA),...
    hE5(topFEA), hE1(topFEA), pU(topFEA), hU5(topFEA), hU1(topFEA),...
    pWW(topFEA), hWW5(topFEA), hWW1(topFEA), 'VariableNames',...
    {'Index' 'FDR' 'pvalueEV' 'hypoEV5' 'hypoEV1' 'pvalueUV' 'hypoUV5'...
    'hypoUV1' 'pvalueWW' 'hypoWW5' 'hypoWW1'});

X1t = X1(topFEA,:);
X2t = X2(topFEA,:);
Xt = [X1t';X2t'];
Y=[1*ones(1,4) 2*ones(1,3)];

T1 = zeros(7, 4);
T2 = zeros(7, 3);
figNum = 1;
figure(figNum);
for i = 1:size(Xt,2)
    Xi = Xt(:,i);
    MdlLinear = fitcdiscr(Xi,Y');

    L = MdlLinear.Coeffs(1,2).Linear;
    t1=L'*Xi(Y==1,:)';
    t2=L'*Xi(Y==2,:)';
    T1(i,:) = t1;
    T2(i,:) = t2;

    figure(figNum), subplot(2,4,i), h1 = histfit(t1);
    figure(figNum), hold on
    figure(figNum), subplot(2,4,i), h2 = histfit(t2);
    h1(1).FaceColor = [1 .8 .8];
%     h1(1).Parent.XLim = [-80 150];
    h2(1).FaceColor = [.8 .8 1];
    h2(2).Color = [0 0 1];
end

figNum = figNum + 1;
corrplot(Xt);

Xt(:,6:7) = []; %% HARD CODED!!!!
classList = {'linear', 'diaglinear', 'quadratic',...
    'diagQuadratic', 'mahalanobis'};

cNum = size(classList,2);
nFeatures = size(Xt,2);

Acc = NaN(cNum,nFeatures);
GammaArr = NaN(cNum,nFeatures);
Se = NaN(cNum,nFeatures);
Sp = NaN(cNum,nFeatures);
PPV = NaN(cNum,nFeatures);
NPV = NaN(cNum,nFeatures);
AUC = NaN(cNum,nFeatures);

%% Classification
distClass = 0;
for c = 1:cNum
    for i = 1:nFeatures
        if (distClass)
            try
                MdlLinear = fitcdiscr(Xt(:,1:i), Y',...
                    'DiscrimType',classList{c});
            catch FDERROR
                fprintf('Failed to fit classifier: %s\n', FDERROR.message);
                continue;
            end

            GammaArr(c,i) = MdlLinear.Gamma;
            resuberror = resubLoss(MdlLinear);
            cvmodel = crossval(MdlLinear,'leaveout','on');
            cvpred = kfoldPredict(cvmodel);

            ConfMat = confusionmat(cvmodel.Y,cvpred);
        else
            cp = cvpartition(Y','LeaveOut');
            order = [1;2];
            
            f = @(xtr,ytr,xte,yte)confusionmat(yte,...
                classify(xte,xtr,ytr,classList{c},...
                         'empirical'),'order',order);
            
            try
                ConfMat = crossval(f, Xt(:,1:i), Y', 'partition', cp);
            catch FDERROR
                fprintf('Failed to fit classifier: %s\n', FDERROR.message);
                fprintf('Error for %s classifier for %i features.\n',...
                    classList{c}, i);
                continue;
            end
            ConfMat = reshape(sum(ConfMat),2,2);
        end
        
        CCell = num2cell(ConfMat);
        [TP, FN, FP, TN] = CCell{:};

        Acc(c,i) = (TP + TN) / (TP + FP + TN + FN);
        Se(c,i) = TP / (TP + FN);
        Sp(c,i) = TN / (FP + TN);
        PPV(c,i) = TP / (TP + FP);
        NPV(c,i) = TN / (TN + FN);
        AUC(c,i) = (Se(c,i) + Sp(c,i)) / 2;
    end
end

perfMea = cat(3,Acc,Se,Sp,PPV,NPV,AUC);

figNum = figNum + 1;
pMarkers = {'h', 'o', '*', 'd', 'x'};
pTitles = {'Accuracy', 'Sensitivity', 'Specificity', 'PPV', 'NPV',...
    'AUC'};
pLineWidth = [1.2, 0.8, 1, 1, 1.2];
pMarkerSize = [6, 8, 8, 6, 8];
for ip = 1:size(perfMea,3)
    for i = 1:size(perfMea,2)
        figure(figNum), subplot(2,3,ip), p = plot(1:5,perfMea(i,:,ip));
        xlim([0 7])
        ylim([0 1.05])
        xlabel('Ranked Features')
        title(pTitles{ip})
        p.LineWidth = pLineWidth(i);
        p.Marker = pMarkers{i};
        p.MarkerSize = pMarkerSize(i);
        figure(figNum), hold on
    end
end

pLegend = {'LDA', 'Diaglinear', 'QDA', 'Diagquadratic', 'Mahalanobis'};
figure(figNum);
pl = legend(pLegend,'Location','southoutside',...
    'Orientation','horizontal','FontSize',12);
rect = [0.45, 0.01, .15, .05];
set(pl, 'Position', rect)
