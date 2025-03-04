/* THIS PROGRAM CALCULATES THE WEIGHTED MEANS AND AVERAGES USING        */
/* THE SUMMARY VARIABLES FROM THE FMLY FILES BASED ON THE CALENDAR YEAR */

OPTIONS PS = 59 LS = 80 MPRINT MLOGIC SYMBOLGEN;

%MACRO SUMVARS;

/*Enter Data Year*/
%LET YEAR4 = 2012;
/*Enter location of the unzipped microdata file*/
/*Be sure to keep the same file structure as found online*/
%LET DRIVE = C:\2012_CEX;




  %LET YEAR2 = %SUBSTR(&YEAR4, 3, 2);
  %LET YR4NEXT = %EVAL(&YEAR4 + 1);
  %LET YR2NEXT = %SUBSTR(&YR4NEXT, 3, 2);
  %LET ERRFLG = N;

  /* GET LIST OF FIELDS AVAILABLE FROM THE INPUT FILE */
  /* REPLACE THIS LIBNAME WITH LIBNAME FOR YOUR DATA LIBRARY */

  LIBNAME INDATA "&DRIVE\INTRVW&YEAR2" ACCESS = READONLY;

  PROC CONTENTS DATA = INDATA.FMLI&YR2NEXT.1 NOPRINT
                OUT = INDCONT (KEEP = NAME);
  RUN;
  
  DATA INDPQ INDCQ;
    LENGTH NAME $32;
    SET INDCONT;
	NAME = UPCASE(NAME);
    IF (LEFT(REVERSE(NAME)) =: 'QC') THEN OUTPUT INDCQ;
    ELSE IF (LEFT(REVERSE(NAME)) =: 'QP') THEN OUTPUT INDPQ;
  RUN;

  /* GET LIST OF REQUESTED FIELDS FROM THE USER FIELDS FILE */
  /* REPLACE THIS FILENAME WITH FILENAME FOR YOUR TEXT FILE */

  FILENAME PARFILE "&DRIVE.\Programs\PUSUMVARS.TXT";

  DATA DSUSRFLD;
    LENGTH ROWLABEL $50;
    INFILE PARFILE DSD;
	INPUT NAME : $CHAR32. ROWLABEL;
	INDENT = VERIFY (NAME, ' ');
	NAME = LEFT (UPCASE (NAME));
	ORDER = _N_;
  RUN;

  DATA DSUSRFLD (DROP = USRNAME)
       DSUSRPQ (KEEP = NAME)
       DSUSRCQ (KEEP = NAME);
    SET DSUSRFLD (RENAME = (NAME = USRNAME));
	NAME = TRIM(LEFT(USRNAME));
	OUTPUT DSUSRFLD;
	NAME = TRIM(LEFT(USRNAME)) || 'PQ';
	OUTPUT DSUSRPQ;
	NAME = TRIM(LEFT(USRNAME)) || 'CQ';
	OUTPUT DSUSRCQ;
  RUN;

  /* CREATE MACRO LISTS OF INPUT & COMPUTED FIELDS */

  PROC SQL NOPRINT;
    SELECT NAME INTO : CQVARS SEPARATED BY ' ' FROM DSUSRCQ;
    SELECT NAME INTO : PQVARS SEPARATED BY ' ' FROM DSUSRPQ;
    SELECT NAME INTO : COMPVARS SEPARATED BY ' ' FROM DSUSRFLD;
  QUIT;
  PROC SORT DATA = DSUSRFLD;
    BY NAME;
  RUN;

  PROC SORT DATA = DSUSRPQ;
    BY NAME;
  RUN;

  PROC SORT DATA = DSUSRCQ;
    BY NAME;
  RUN;

  /* ERROR IF THE SAME FIELD NAME IS REPEATED MORE THAN ONCE IN USER FILE */
  
  DATA DSUSRFLD;
    SET DSUSRFLD;
    BY NAME;
    IF (^ (FIRST.NAME & LAST.NAME)) THEN DO;
	  CALL SYMPUT('ERRFLG', 'Y');
      PUT 'ERROR: DUPLICATE VARIABLE NAME IN FIELD LIST FILE. ' NAME=;
	END;
  RUN;
  
  /* MATCH FIELDS FROM STUB FILE AGAINST INPUT DATA FIELDS                         */
  /* IF ANY OF THE REQUESTED FIELDS NOT FOUND IN INPUT DATA GENERATE ERROR LISTING */
  /* OTHERWISE CREATE A FINAL LIST OF EXPENDITURE FIELDS TO PROCESS                */

  DATA DSPQ;
    MERGE DSUSRPQ (IN = INUSRPQ)
          INDPQ (IN = INDPQ);
	BY NAME;
	IF (INUSRPQ);
    IF (INDPQ) THEN OUTPUT DSPQ;
	ELSE DO;
	  CALL SYMPUT('ERRFLG', 'Y');
      PUT 'ERROR: REQUESTED VARIABLE NOT FOUND IN INPUT DATASET. ' NAME=;
	END;
  RUN;      

  DATA DSCQ;
    MERGE DSUSRCQ (IN = INUSRCQ)
          INDCQ (IN = INDCQ);
	BY NAME;
	IF (INUSRCQ);
    IF (INDCQ) THEN OUTPUT DSCQ;
	ELSE DO;
	  CALL SYMPUT('ERRFLG', 'Y');
      PUT 'ERROR: REQUESTED VARIABLE NOT FOUND IN INPUT DATASET. ' NAME=;
	END;
  RUN;      

  %IF (&ERRFLG = Y) %THEN %DO;
    %PUT PROGRAM TERMINATING.;
    %GOTO EXIT;
  %END;

  /* THIS STEP PULLS IN THE WEIGHT VARIABLES AND SUMMARY VARIABLES       */
  /* MO_SCOPE IS USED TO ADJUST THE POPULATION WEIGHTS FOR CALENDAR YEAR */
  /* SEE DOCUMENTATION, SECTION V. ESTIMATION PROCEDURES - A.1.B.        */
  /* CALENDAR PERIOD VERSUS COLLECTION PERIOD, FOR MORE INFORMATION.     */

  DATA FMLY (KEEP = NEWID MFNLWT21 FINLWT21 &COMPVARS);
    SET INDATA.FMLI&YEAR2.1X (IN = IN1)
        INDATA.FMLI&YEAR2.2 (IN = IN2)
        INDATA.FMLI&YEAR2.3 (IN = IN3)
        INDATA.FMLI&YEAR2.4 (IN = IN4)
        INDATA.FMLI&YR2NEXT.1 (IN = IN5);

    IF (IN1) THEN MO_SCOPE = INPUT(QINTRVMO, 2.) - 1;
    ELSE IF (IN5) THEN MO_SCOPE = 4 - INPUT(QINTRVMO, 2.);
    ELSE MO_SCOPE = 3;
	/* THIS IS THE NEW (CALENDAR-YEAR ADJUSTED) POPULATION WEIGHT TO BE SUMMED FOR TOTAL POP */
    MFNLWT21 = FINLWT21 * MO_SCOPE / 12;

	/* THIS ARRAY READS IN ALL PQ VARIABLES: EXPENDITURES FROM PREVIOUS QUARTER */
    ARRAY PQARR (*) &PQVARS;
    /* THIS ARRAY READS IN ALL CQ VARIABLES: EXPENDITURES FROM CURRENT QUARTER */
    ARRAY CQARR (*) &CQVARS;
    /* THIS ARRAY COMPILES THE EXPENDITURE VARIABLES TO MATCH TO THE DESIRED CALENDAR YEAR */
    ARRAY COMPARR (*) &COMPVARS;
    DO I = 1 TO DIM(COMPARR);
      /* IF THE INTERVIEW IS IN THE FIRST QUARTER OF THE DESIRED CALENDAR YEAR,             */
      /* THEN ALL EXPENDITURES IN THE PREVIOUS QUARTER WILL FALL IN THE LAST CALENDAR YEAR, */
      /* SO ONLY CURRENT QUARTER EXPENDITURES SHOULD BE INCLUDED.                           */
      IF (IN1) THEN COMPARR{I} = CQARR{I};
      /* IF THE INTERVIEW IS IN THE FIFTH QUARTER, THEN ALL CURRENT QUARTER EXPENDITURES WILL FALL   */
      /* OUTSIDE THE CURRENT CALENDAR YEAR, SO ONLY PREVIOUS QUARTER EXPENDITURES SHOULD BE INCLUDED */
      ELSE IF (IN5) THEN COMPARR{I} = PQARR{I};
      ELSE COMPARR{I} = SUM(PQARR{I}, CQARR{I});
    END;
  RUN;

  /* SUM THE CALENDAR YEAR WEIGHTS TO CREATE THE TOTAL POPULATION */
  
  PROC SUMMARY DATA = FMLY;
	VAR MFNLWT21;
  	OUTPUT OUT = POP (DROP = _TYPE_ _FREQ_) SUM = TOTPOP;
  RUN;

  PROC PRINT DATA = POP;
	TITLE 'TOTAL POPULATION';
  RUN;

  /* CALCULATE THE WEIGHTED AGGREGATES FOR THE POPULATION */
  
  PROC SUMMARY DATA = FMLY SUM;
	VAR &COMPVARS;
	WEIGHT FINLWT21;
	OUTPUT OUT = AGG (DROP = _TYPE_ _FREQ_) SUM = &COMPVARS;
  RUN;

  PROC PRINT DATA = AGG;
	TITLE 'AGGREGATES';
  RUN;
  
  /* CALCULATE THE AVERAGE EXPENDITURE FOR THE SUMMARY VARIABLE OF CHOICE */
  /* BY DIVIDING THE AGGREGATES BY THE TOTAL POPULATION                   */
  
  DATA AVERAGES (DROP = I);
    SET POP;
	SET AGG;
	ARRAY AGGARR (*) &COMPVARS;
	ARRAY AVGARR (*) &COMPVARS;
	DO I = 1 TO DIM(AGGARR);
		AVGARR{I} = AGGARR{I} / TOTPOP;
	END;
  RUN;

  /* MERGE WITH THE ROW LABELS AND PRINT THE REPORT */
  
  PROC TRANSPOSE DATA = AVERAGES OUT = AVERAGES (RENAME = (_NAME_ = NAME COL1 = VALUE));
  RUN;

  PROC SORT DATA = AVERAGES;
    BY NAME;
  RUN;
  
  DATA DSFINAL;
    LENGTH NAME $32;
    MERGE AVERAGES (IN = INAVER)
          DSUSRFLD (IN = INUSRFLD);
    BY NAME;
    IF (INAVER);
    IF (^ INUSRFLD) THEN DO;
      ORDER = 0;
      INDENT = 1;
      ROWLABEL = 'TOTAL POPULATION';
    END;
  RUN;

  PROC SORT DATA = DSFINAL;
    BY ORDER;
  RUN;

  DATA _NULL_;
    FILE PRINT;
    RETAIN GEN_IND 4;
    SET DSFINAL;
    PUT @(GEN_IND + INDENT) ROWLABEL 
        @66 VALUE COMMA14.;
    TITLE 'ANNUAL AVERAGE EXPENDITURE';
    TITLE4 ' ';
  RUN;
  
  %EXIT:

%MEND SUMVARS;

%SUMVARS

