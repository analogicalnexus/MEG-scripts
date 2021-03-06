%%Basic script for presenting sentence or priming study in EEG, MEG or fMRI
%%First version 6/3/11 Ellen Lau
%%Modified by Cybelle Smith  Fall 2011 (10/10/11)
%%Modified for MEG by Ellen Lau & Allison Fogel, Fall 2012
%%Modified back to EEG by Ellen Lau & Allison Fogel, Spring 2013
%%Modified to be compatible with all 3 techniques, Ellen Lau, Summer 2013
%%Modified for EEG (Sandcastle follow-up), Glynis & Wing Yee, Summer 2013

%%%%%%%%% *******************
%%HEAVILY Mofified by Wm. Matchin, Fall 2014, only works for stegosaurus!
%%%%%%%%% *******************

%%Partially based on code from Scott Burns, MGH

%%Needs class definition file exptblock.m to exist in the same directory

%%Useful fact: if the program freezes while the screen is black you can
%%escape by typing ctrl-c and hitting return, then "sca" and hitting return 
%%(you may need to do it more than once 

%%If you're trying to understand the script for the first time, try collapsing
%%all of the functions so you can see the overarching str`ucture

%%Which recording method? MRI, EEG, MEG

%%%%%%%%%%%%Functions for running experiment%%%%%%%%%%%%%%%%
function expt = WordPres_WM2() 
    %%%This is the main function that controls the entire process, from reading
    %%%in input parameters to actually running the experiment
    
    %% Initialize keyboard
    KbCheck;
    
    ClockRandSeed;

    
    %% Select experiment and parameter files and enter subject ID.
    [exptFileName, exptPath] = uigetfile('*.expt', 'Select experiment file');
    [paramFileName, paramPath] = uigetfile('*.par', 'Select parameter file',exptPath);
    subjID = input('Enter subject ID: ', 's');

    %% Initialize file names: strip off exptFile extension, generate log
    % and rec filenames
    exptFilePrefix = strrep(exptFileName,'.expt','');
    
    par.logFileName = strcat(exptPath,'logs/',subjID,'_',exptFilePrefix,'.log');
    %%logs events in same directory as experiment file
    
    recFileName = strcat(exptPath,'logs/',subjID,'_',exptFilePrefix,'.rec');
    %%logs parameters in same directory as experiment file

    
    %% Create empty log and rec files, first test that they don't already exist
    fExist = fopen(par.logFileName, 'r');
    
    if fExist == -1
        fid = fopen(par.logFileName,'w');
        if fid == -1
            error('Cannot write to log file.')
        end
        fclose(fid);
    else
        error('log file with this name already exists')
    end
    
    fExist = fopen(recFileName, 'r');

    if fExist == -1
        fid = fopen(recFileName,'w');
        if fid == -1
            error('Cannot write to rec file.')
        end
        fclose(fid);
    else
        error('rec file with this name already exists')
    end

    %% ReadParameterFile stores the parameters in the struct 'par'.
    paramFileNameAndPath = strcat(paramPath,paramFileName);
    par = ReadParameterFile(paramFileNameAndPath,par);
    fprintf('Parameter file read');

    %% ReadExptFile preloads stims, returning a struct, 'expt', 
    %which stores all the data necessary for running the experiment, besides the parameters.
    exptFileNameAndPath = strcat(exptPath,exptFileName);
    expt = ReadExptFile(exptFileName,exptPath,par);
    fprintf('Expt file read');

    %% WriteRecFile writes out the parameters, current time and subjID to record
    %what parameters were used each specific time each experiment was run.
    WriteRecFile(recFileName,par,subjID, exptFileNameAndPath,paramFileNameAndPath);
    fprintf('Rec file written')

    %%% Configure the data acquisition device
    
    if strcmp(par.scanner,'EEG')
        par.di = DaqDeviceIndex; % the DaqDeviceIndex function returns the 
        % index of the port assigned to the daq device so you can refer to 
        % it in the rest of your script
        
        DaqDConfigPort(par.di,1,0); % this configures the daq port to either 
        % send output or receive input. the first number refers to which 
        % port of the daq device, A (0) or B (1). The second number refers 
        % to output (0) or input (1)
        
        DaqDOut(par.di,1,0); % this zeros out the trigger line to get started
    end
    
    if strcmp(par.scanner, 'MEG')
        par.pulsewidth = .005;
        open = daqhwinfo('parallel');
        par.DIO1 = digitalio('parallel','LPT1');
        par.DIO2 = digitalio('parallel','LPT1');
        outreg = addline(par.DIO1, 0:7, 0, 'out');
        inreg = addline(par.DIO2, 0:4, 1, 'in');

        active_triggers = [130:156];
        ExptTriggers = active_triggers(1:par.nTriggers)
        par.triggerStruct = SetUpTriggerLines(ExptTriggers)
    end
    
    if strcmp( par.scanner, 'MRI') %&& par.IsMNCScan
        par.MNCserial = activateMNCserial;
    end
    %%% RunExperiment is the function that controls presentation of
    %%% slides and stimuli
    par = RunExperiment(expt,par);

end

function par = RunExperiment(expt,par)
    %%% RunExperiment controls presentation of slides and stimuli

	%%% Grab a time baseline for the entire experiment and send a trigger to log
	baseTime = GetSecs();
	
	%%% Send a trigger to index the beginning of the experiment
	%%% presentation-  is this necessary?
    if strcmp(par.scanner,'EEG')
        DaqDOut(par.di,1,par.beginTrigger); %Turn trigger on
        DaqDOut(par.di,1,0); %Turn trigger off     
    end
    
	%%% Set up screen
    par.screenNumber = 0;
    
	par.wPtr = Screen('OpenWindow',par.screenNumber,0,[],32,2);  % This
    % command outputs a lot of text to the Matlab window
    
    %% Hide cursor (WM 10/29/14)
    %HideCursor;
    
	par.black = BlackIndex(par.wPtr);
	
    %%% Present slides and stimuli
	for i = 1:length(expt)
		curritem = expt{i};
		if (strcmp(class(curritem),'expblock'))
            %%% RunBlock is the critical function that presents text stimuli
            fprintf('presenting stimulus block')
%%%            if strcmp(par.scanner,'EEG')
%%%                DaqDOut(par.di,1,par.blockTrigger);                
%%%            end
			par = RunBlock(curritem,par);	
        else
            %%% RunTextSlide presents instruction screens
			RunTextSlide(curritem,par);
            fprintf('presenting slide')
        end		
	end
	
	sca;  %%%End of experiment!
end

function par = RunBlock(stimBlock,par)
    %% Runs the block
	numItems = length(stimBlock.stimulusMatrix);
    
    ClearButtonPress()
    if strcmp(par.scanner,'MRI')
        startsec=startExp(par.wPtr,par.MNCserial);
    elseif strcmp(par.scanner,'testMRI')
        startsec=startExp(par.wPtr);
    end

    if strcmp(par.scanner,'MRI') | strcmp(par.scanner,'testMRI')
        results = InitResults;
        timeToLog = startsec
        startBlockTime = startsec;  %%%GetSecs();
        results = UpdateResults(results,timeToLog, 'MRI', 999);
        WriteLogFile(results,par.logFileName);
    else
        startBlockTime = [];
    end
    ClearButtonPress()
 
    
    %%%For each trial in the block:
    
	for i = 1:numItems

        %%%Initialize results, currentQuestion
        results = InitResults;
        currentQuestion = stimBlock.questionList{i};
        currQuestionTrigger = stimBlock.questionTriggers{i};

        %%%Present item
        results = RunItem(stimBlock,i,results,par,startBlockTime);
			
        %%%Present question if exist (doesn't currently work for MRI)
		if ~isempty(currentQuestion)
            results = RunQuestion(currentQuestion,currQuestionTrigger, results,par);            				
        end
		
        %%%Log all results after trial is complete
		WriteLogFile(results,par.logFileName);
        
        %%%If not self-paced, wait ITI before continuing
        if par.selfPaced == 0
            Screen('FillRect',par.wPtr,par.black);
			Screen('Flip',par.wPtr);
			WaitSecs(par.ITI);
        elseif par.selfPaced == 1
            ClearButtonPress;
            %%%Wait for button press to continue to next trial
            Screen('TextSize',par.wPtr,par.slideTextSize);
            DrawFormattedText(par.wPtr,'Press any button to continue.','center','center',WhiteIndex(par.wPtr));
            Screen(par.wPtr,'Flip');
            GetButtonPress([par.moveOnButton],[par.moveOnTrigger],par,0);
        end
	end

end

function RunTextSlide(currTextSlide,par)
    %%%Present 'slide' of instructions. Responses to slides aren't recorded
    Screen('TextSize',par.wPtr,par.slideTextSize);
    DrawFormattedText(par.wPtr,currTextSlide,'center','center',WhiteIndex(par.wPtr));
    Screen('Flip',par.wPtr);
    ClearButtonPress;
    GetButtonPress([par.moveOnButton],[par.moveOnTrigger],par,0);
end

function results = RunItem(stimBlock,i,results,par,startBlockTime)


        timeZeroZero = GetSecs;
        %%%Initialize currentItem, TriggerList
		currentItem = stimBlock.stimulusMatrix{i};  %This is the current item (trial) being presented
		currentItemTriggerList = stimBlock.triggerMatrix{i}; %This is the current list of triggers for that item
		numWords = length(currentItem);
         
        if strcmp(par.scanner,'MRI')||strcmp(par.scanner,'testMRI')
            currentOnset = stimBlock.stimulusOnsets(i);
        end
        
        
        % *********************************************
        % ******* ADD JITTER HERE WM 10/22/14 *********
        % *********************************************
        
        % first, make sure screen is black
        Screen('FillRect',par.wPtr,par.black);
		Screen('DrawingFinished',par.wPtr);
        Screen('Flip',par.wPtr);
        
        % wait 1-2 seconds before onset of trial
        WaitSecs('UntilTime',timeZeroZero+.8+rand);
        
        
        timeZero = GetSecs;
        
        %% Start by presenting fixation cross and subsequent blank screen
        Screen('TextSize',par.wPtr,par.textSize);
		DrawFormattedText(par.wPtr,'+','center','center',WhiteIndex(par.wPtr));
		Screen('DrawingFinished',par.wPtr);
        Screen('Flip',par.wPtr);
        
        Screen('FillRect',par.wPtr,par.black);
		Screen('DrawingFinished',par.wPtr);
        
        if strcmp(par.scanner,'MRI') || strcmp(par.scanner,'testMRI')
            currentItemOnset = str2num(currentOnset{1})+startBlockTime;
            Screen('Flip',par.wPtr,currentItemOnset-par.IFI);
        else
            % modified here by WM 10/29/14
            %WaitSecs(par.fixDuration);
            WaitSecs('UntilTime',timeZero+par.fixDuration);
            Screen('Flip',par.wPtr);
            
            % modified here by WM 10/29/14
            %WaitSecs(par.IFI);
            fixTime = timeZero+par.fixDuration+par.IFI;
            WaitSecs('UntilTime',fixTime);
        end
        
        
        %% Present the item itself, word by word
        %%%This loop should have as little as possible inside it to speed timing performance
        %%% ********* Will need to account for font changes here! *********
        
		for w = 1: (numWords - 1)
			currentWord = currentItem{w};
			
            % this should be the trigger number of the current trial
            % use this to set font size
            currentTrigger = currentItemTriggerList{w};
            
            % ******** MODIFIED WM 10/22/14 *******
            % odd trigger numbers are small font, even numbers large font
            currentFontSize = 26;
            
            Screen('TextSize',par.wPtr,currentFontSize);

            %%Present word, send trigger, show subsequent blank screen
 			DrawFormattedText(par.wPtr,currentWord,'center','center',WhiteIndex(par.wPtr));
			Screen('DrawingFinished',par.wPtr);
                        
            if strcmp(par.scanner,'MRI')||strcmp(par.scanner,'testMRI')
                timeToLog = Screen('Flip',par.wPtr,currentItemOnset)-startBlockTime;
            end

            if strcmp(par.scanner,'EEG')
                timeToLog = Screen('Flip',par.wPtr);
    			DaqDOut(par.di,1,currentTrigger); %Turn trigger on
        		DaqDOut(par.di,1,0); %Turn trigger off 
            end
            if strcmp(par.scanner,'MEG')
                timeToLog = Screen('Flip',par.wPtr);
                par.triggerStruct.WhichTrigger(currentTrigger).outval
                putvalue(par.DIO1.Line(1:8),par.triggerStruct.WhichTrigger(currentTrigger).outval)
                waitsecs(par.pulsewidth);
                putvalue(par.DIO1.Line(1:8),0);
            end
            if strcmp(par.scanner,'testMEEG')
                timeToLog = Screen('Flip',par.wPtr);
            end
            
            % modified by Wm. Matchin 10/28/14 to wait until a certain time
            %WaitSecs(par.wordDuration);
            WaitSecs('UntilTime',fixTime+par.wordDuration);
            
			Screen('FillRect',par.wPtr,par.black);
			Screen('Flip',par.wPtr);
			
            firstWordTime = fixTime+par.wordDuration+par.IWI;
            
            
            % modified by Wm. Matchin 10/28/14 to wait until a certain time
            %WaitSecs(par.IWI);
            WaitSecs('UntilTime',firstWordTime);

            % Add data about current word presentation to data structure
            % containing results to log (but don't yet log it)
			results = UpdateResults(results,timeToLog, currentWord, currentTrigger);
			
        end
        
        %%Present final word of trial , possibly for a different duration
        
        currentWord = currentItem{numWords};
        currentTrigger = currentItemTriggerList{numWords};
        
        % *********************************************
        % ***** ADD SUBJ RESPONSE HERE WM 10/22/14 ****
        % *********************************************
        ClearButtonPress;

        %%Present word, send trigger, show subsequent blank screen
        DrawFormattedText(par.wPtr,currentWord,'center','center',WhiteIndex(par.wPtr));
        Screen('DrawingFinished',par.wPtr);
        
        if strcmp(par.scanner,'MRI')||strcmp(par.scanner,'testMRI')
            timeToLog = Screen('Flip',par.wPtr); 
            timeToLog = timeToLog-startBlockTime;
        end
       
        if strcmp(par.scanner,'EEG')
            timeToLog = Screen('Flip',par.wPtr); 
            DaqDOut(par.di,1,currentTrigger); %Turn trigger on
            DaqDOut(par.di,1,0); %Turn trigger off
        end
        
        if strcmp(par.scanner,'MEG')
            timeToLog = Screen('Flip',par.wPtr); 
            putvalue(par.DIO1.Line(1:8),par.triggerStruct.WhichTrigger(currentTrigger).outval)
            waitsecs(par.pulsewidth);
            putvalue(par.DIO1.Line(1:8),0);
        end
        
        if strcmp(par.scanner,'testMEEG')
            timeToLog = Screen('Flip',par.wPtr);
        end
        
        WaitSecs('UntilTime',firstWordTime+par.finalWordDuration);
        
        
        % *********************************************
        % ***** ADD SUBJ RESPONSE HERE WM 10/22/14 ****
        % *********************************************
        
        
        % Here, in MRI you want to end trial with a fixation trial that
        % will be on until the beginning of the next stim; in EEG/MEG you
        % want to flip to a blank screen for ITI
        if strcmp(par.scanner,'MRI')||strcmp(par.scanner,'testMRI')
            Screen('TextSize',par.wPtr,par.textSize);
            DrawFormattedText(par.wPtr,'+','center','center',WhiteIndex(par.wPtr));
            Screen('DrawingFinished',par.wPtr);
            Screen('Flip',par.wPtr);
        else
            Screen('FillRect',par.wPtr,par.black);
            Screen('Flip',par.wPtr);
        end
        
        %%%% 12/11/14 ADD inter-word interval time here to ensure that some
        %%%% time elapses before the question appears
        WaitSecs('UntilTime',firstWordTime+par.finalWordDuration+par.IWI)
        
        % Add data about current word presentation to data structure
        % containing results to log (but don't yet log it)
        results = UpdateResults(results,timeToLog, currentWord, currentTrigger);
        
        
end

function results = RunQuestion(currentQuestion, currQuestionTrigger, results, par)
        %%%Present question
        % modified here by WM 12/11/14 - don't wait here, wait during the
        % 'run block' function
        %WaitSecs(par.IQI);
        ClearButtonPress;
        Screen('TextSize',par.wPtr,par.questionTextSize);%
        DrawFormattedText(par.wPtr,currentQuestion,'center','center',WhiteIndex(par.wPtr));
        Screen('DrawingFinished',par.wPtr);
        timeToLog= Screen('Flip',par.wPtr);
        if strcmp(par.scanner,'EEG')
            DaqDOut(par.di,1,currQuestionTrigger);
            DaqDOut(par.di,1,0);
        end
        if strcmp(par.scanner,'MEG')            
            putvalue(par.DIO1.Line(1:8),par.triggerStruct.WhichTrigger(currQuestionTrigger).outval)
            waitsecs(par.pulsewidth);
            putvalue(par.DIO1.Line(1:8),0);
        end
        results = UpdateResults(results,timeToLog, currentQuestion, currQuestionTrigger);

        %%%Capture button press
        [reactionTime, button, buttonTrigger, par] = GetButtonPress(par.buttonList,par.buttonTriggerList,par,1);
        % -1 means the subject did not hit one of the button choices during the allotted time.
        if(button~=-1)
           button = KbName(button);
        else
           button = 'no_response';
        end

        results = UpdateResults(results,reactionTime, button, buttonTrigger);
end


%%%%%%%%%%%%Reading parameters%%%%%%%%%%%%%%%%%%%%%%%%%%
function par = ReadParameterFile(paramFileName, par)
%Reads the parameter file.  For an example of the format the
%parameter file should be in, see example.par in the folder 
%example_experiment on the desktop.

	fid = fopen(paramFileName,'rt');
	
	if (-1 == fid)
		error('Could not open experiment parameters file.')
	end
	
	textLine = fgets(fid);
	
	while (-1 ~= textLine)
		%comments in the parameter file are on lines starting with '#'
		if(textLine(1)=='#')
			textLine = fgets(fid);
			continue
        end
        
        fxnToEval = strcat('par.',textLine,';');      
		if (~strcmp(fxnToEval,'par.;'))
			%fprintf(strcat('this is the function to evaluate: ',fxnToEval,'\n'));
			eval(fxnToEval); % This looks fancy, but just a way to do assignment of par variables in the text file
		end
		textLine = fgets(fid);
	end
	
	fclose(fid);
end


%%%%%%%%%%%%Reading experimental materials%%%%%%%%%%%%%%

function expt = ReadExptFile(exptFileName,exptPath,par)
    exptFileNameAndPath = strcat(exptPath,exptFileName);
    expt = {};
    stimFiles = {};
    fid = fopen(exptFileNameAndPath, 'r');
    if fid == -1
        error('Cannot open experiment file.')
    end
    textLine = fgetl(fid);  %fgetl reads a single line from a file
    
    %% Read in list of filenames of slides and stimlists to be presented
    ii = 1;
    while (-1 ~= textLine)
        C = textscan(textLine, '%q %d'); %use textscan to separate it
        stimFiles{ii} = strcat(textLine);
        ii = ii + 1;
        textLine = fgetl(fid);      
    end 
    fclose(fid);
    
    %% For each slide or stimlist filename listed, check that it exists, prompt for
    %%user entry if it does not, and then add the contents of the file to the expt
    %%structure by using ReadStimFile
    
    nFiles = length(stimFiles);
    
    for ii = 1:nFiles
        stimFileNameAndPath = strcat(exptPath,stimFiles{ii})
        fid = fopen(stimFileNameAndPath, 'r');
        while fid == -1
            prompt = horzcat('Set filename for ',stimFiles{ii},': ');
            stimFiles{ii} = input(prompt, 's');
            stimFileNameAndPath = strcat(exptPath,stimFiles{ii});
            fid = fopen(stimFileNameAndPath, 'r');
        end
        
        expt = ReadStimFile(stimFileNameAndPath,expt,par);
        expt{end}
        
        fclose(fid);
    end

end

function expt = ReadStimFile(stimFile,expt,par)

    %% Open a file containing stimuli
    fprintf('%s\n',stimFile);
    fid = fopen(stimFile, 'r');
    textLine = fgets(fid);  %fgets reads a single line from a file, keeping new line characters.
    
    %%%Get onsets for FMRI, if reading stimlist
    stimCheck = strfind(stimFile,'stim');
    if (strcmp(par.scanner,'MRI') || strcmp(par.scanner,'testMRI')) && ~isempty(stimCheck)
         onsetFile = strcat(stimFile(1:(size(stimFile,2)-4)),'_onsets.txt');
         fprintf('%s\n',onsetFile);
         onset_fid = fopen(onsetFile, 'r');
    end
    
    %% For each line of the stim file, add content to expt structure

    itemNum = 1;  %The number of the current stimulus item.
    stimBlock = InitBlock;  %Information in the expt structure is organized by objects of class 'exptblock'
    stimBlock.name = stimFile;

    while (-1 ~= textLine)
        C = textscan(textLine, '%q %d'); %use textscan to separate line into 'text' 'number' pairs.
        numStimWords = length(C{1});
        
        %If there is a blank line, skip it and get the next line.
        if (numStimWords == 0)
            %fprintf('there is a blank line\n');
            textLine = fgets(fid); 
            continue
        end
       
        
        %% Two cases, one for files containing textslides, one for regular stim lists
        %Both of these need to be able to loop, because you can have more than one text
        %slide in a file (e.g. an intro.txt file with several slides)

        if strcmp(C{1}{1},'<textslide>')
            %% If the first token in the current line is '<textslide>', add 
            % the current block of stimuli (if it is not empty) to expt,
            % reset the current block of stimuli, then read from the file 
            % using ReadTextSlide until you hit '</textslide>'
            % and add the textslide to the experiment.
            
            %fprintf('textslide identified\n');
            expt{1,length(expt)+1} = ReadTextSlide(textLine,fid);
            itemNum=1;
            textLine = fgets(fid);   
       
        else
            %% Otherwise, treat like a structured list of text stimuli
            
              for jj = 1:numStimWords        
                  if strcmp(C{1}{jj},'?') 
                         stimBlock.questionTriggers{itemNum} = C{2}(jj);
                         stimBlock.questionList{itemNum} = C{1}{jj+1};
                         if(jj==1) %%if no words prior to the question, create a blank item and trigger
                             stimBlock.stimulusMatrix{itemNum}{jj} = [];
                             stimBlock.triggerMatrix{itemNum}{jj} = [];
                         end
                         %fprintf('added a question and question trigger\n');
                      break
                  else
                      stimBlock.questionList{itemNum} = [];  %%if no question, create an empty cell as a place holder
                      stimBlock.questionTriggers{itemNum} = []; %ditto for the question triggers
                  end
                  stimBlock.stimulusMatrix{itemNum}{jj} = C{1}{jj};
                  stimBlock.triggerMatrix{itemNum}{jj} = C{2}(jj);
                  %fprintf('added a stimulus and trigger\n');
              end
              
        end
        
        if (strcmp(par.scanner,'MRI')||strcmp(par.scanner,'testMRI')) && ~strcmp(C{1}{1},'<textslide>')
            onsetLine = fgets(onset_fid);  %fgets reads a single line from a file, keeping new line characters.
            onsetLine;
            stimBlock.stimulusOnsets{itemNum} = onsetLine;
        end
          
        itemNum = itemNum + 1;
        textLine = fgets(fid); 
          
    end
    
    %% Now the loop is finished, so add this block of stimuli to the experiment, if it is not empty.
    if (~BlockEmpty(stimBlock))
        expt{1,length(expt)+1} = stimBlock;
        %fprintf('block added\n');
    end
    
    fclose(fid);
    
end

function blockempty = BlockEmpty(block)
%Check that the block is not empty.
    blockempty = ((length(block.stimulusMatrix) == 0)...
        && (length(block.triggerMatrix) == 0)...
        && (length(block.questionList) == 0)...
        && (length(block.questionTriggers) == 0));
end

function textslide = ReadTextSlide(textLine,fid)
%% Fills up textslide variable with text to be presented on single screen
    textslide = [];
    while (-1 ~= textLine)
         C = textscan(textLine,'%q');
         if (length(C{1}) == 0)
             textslide = strcat(textslide,'\n');
             textLine = fgets(fid);
             continue
         end
         if strcmp(C{1}{1},'<textslide>')
             textLine = fgets(fid);
             continue
         end
         if strcmp(C{1}{1},'</textslide>')
             break;
         else
             textslide = strcat(textslide,textLine,'\n');
         end
         textLine = fgets(fid);

    end
end
        
function stimBlock = InitBlock
    stimBlock = expblock;  %%%Define stimBlock as a member of the class expblock, defined in expblock.m
    stimBlock.stimulusMatrix = [];
    stimBlock.triggerMatrix = [];
    stimBlock.questionList = {};
    stimBlock.questionTriggers = {};
    %stimBlock.stimulusOnsets = [];
end

 
%%%%%%%%%%%%Writing results%%%%%%%%%%%%%%%%%%%%%%%
function results = InitResults
	results.times = [];
	results.words = {};
	results.triggers = {};
end

function results = UpdateResults(results, timeToLog, currentWord, currentTriggers)
    
   results.times = AddEntry(results.times,timeToLog);
   results.words = AddEntry(results.words,currentWord);
   results.triggers = AddEntry(results.triggers,currentTriggers);
end
 
function WriteLogFile(results,logFileName)
	fid = fopen(logFileName,'a');
	while(fid == -1)
		logFileName = input('There was an error opening the log file.  Please reenter the log filename:', 's');
		fid = fopen(logFileName,'a');
	end
	
	fmt = '%.3f\t%s\t%s\n';  %%controls formatting of output
	for x = 1:length(results.times)
	   currentTriggers = TriggerListToString(results.triggers{x});
	   fprintf(fid,fmt,results.times{x},results.words{x},currentTriggers);
	end
	fclose(fid);

end

function WriteRecFile (recFileName,par,subjID, exptFileNameAndPath,paramFileNameAndPath)
	fid = fopen(recFileName,'a');
	if fid == -1
		error('Cannot write to rec file.')
	end
	fmt = '%s%s\n';
	fprintf(fid,fmt,'Experiment File:',exptFileNameAndPath);
	fprintf(fid,fmt,'Parameter File:',paramFileNameAndPath);
	fprintf(fid,fmt,'Date:',datestr(now));
	fprintf(fid,fmt,'Subject ID:',subjID);
	fprintf(fid,'%s\n','Parameters:');
    par.toString = ParToString(par);
	parstrings = regexp(par.toString,'\\n','split');
	for i = 1:length(parstrings{1})
		%fprintf(1,'%s\n',char(parstrings{1}{i}));
		fprintf(fid,'%s\n',char(parstrings{1}{i}));
	end
	fclose(fid);
end

function str = ParToString(par)
%Returns a string value encoding all the parameters stored in the
%variable par, for writing out to the .rec file
	str = '';
	par_fields = fieldnames(par);
	nfields = length(par_fields);
	if (nfields < 1)
		fprintf('No parameters were entered! Check the parameter file.');
		return
	end
	str = par_fields(1);
	if (nfields > 1)
		for (fieldindex = 2:nfields)
			field = par_fields(fieldindex);
			value = eval(strcat('par.',char(field),';'));
			if(~strcmp(class(value),'string'))
				value = num2str(value);
			end
			str = strcat(str,'\n',field,':',value);
			%fprintf(char(strcat(str,'\n#####\n')));
		end
	end
end


%%%%%%%%%%%%%Gathering responses%%%%%%%%%%%%%%%%

function [reactionTime, button, buttonTrigger, par] = GetButtonPress(buttons,buttonTriggers,par,timed)
%% Waits for a button press by the user of the buttons whose numbers (found using KbName) 
%are specified in the arry of buttons. Send the corresponding trigger for that button, as specified in
%the array buttonTriggers. If the boolean value timed == 1, after par.qDuration seconds the function ends.  
%If timed == 0, waits forever until the user types one of the specified
%buttons.
    begWaitTime = GetSecs();
    timeCutoff = begWaitTime + par.qDuration;                    
    flag = 0;
    button = -1;
    buttonTrigger = -1;
    
    %% Loop that waits for a response or breaks if timeCutoff is exceeded
    while (true);
        [keyDetect,reactionTime,keyCode] = KbCheck(-1);
        %is there a faster way to compare each button??  Can we do this simultaneously for all buttons??
        for (i = 1:length(buttons));
            if (keyCode(buttons(i)));
                if strcmp(par.scanner,'EEG')
                    DaqDOut(par.di,1,buttonTriggers(i));
                    DaqDOut(par.di,1,0);
                end
                if strcmp(par.scanner,'MEG')
                    putvalue(par.DIO1.Line(1:8),par.triggerStruct.WhichTrigger(buttonTriggers(i)).outval)
                    waitsecs(par.pulsewidth);
                    putvalue(par.DIO1.Line(1:8),0);
                end
                button = buttons(i);
                buttonTrigger = buttonTriggers(i);
                flag = 1;
                break;
            end
        end
        
        %%This part just allows you to break if a button was pressed
        if (flag == 1);
            break;
        end

        if (timed && GetSecs() > timeCutoff);
            break;
        end
    end
end

function ClearButtonPress()
%% Makes sure no buttons are being pressed/held down before get the new button press.
%This is important for when, for example, two textslides are one after the
%other, or for any case when one button press triggers another stage of the
%experiment that can be moved on from by pressing the same button that ended the last
%stage.
    while(true)
        [keyDetect,reactionTime,keyCode] = KbCheck(-1);
        if(~keyDetect)
            break;
        end
    end
end


%%%%%%%%%%%%Misc functions%%%%%%%%%%%%%%%%%%%%%%%%
function triggerString = TriggerListToString(triggerList)
    if(length(triggerList) < 1)
        triggerString = 'no triggers sent';
        return
    end
    triggerString = int2str(triggerList(1));
    if (length(triggerList)>1)
         for (i = 2:length(triggerList))
                triggerString = strcat(triggerString,', ',int2str(triggerList(i)));
         end
    end
end

function list = AddEntry(list,entry)
    if (length(list)<1)
        list{1} = entry;
    else
        list{length(list)+1} = entry;
    end
end


