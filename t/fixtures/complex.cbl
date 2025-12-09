       IDENTIFICATION DIVISION.
       PROGRAM-ID. TEST-COBOL.
       ENVIRONMENT DIVISION.
       INPUT-OUTPUT SECTION.
       FILE-CONTROL.
           SELECT IN-FILE ASSIGN TO 'INPUT.DAT'.
           SELECT OUT-FILE ASSIGN TO OUT-DAT.
       DATA DIVISION.
       WORKING-STORAGE SECTION.
       
       * COPY statement
           COPY MY-COPYBOOK.
           
       PROCEDURE DIVISION.
       MAIN-LOGIC.
      *    Comment line (Should be ignored)
      *    CALL 'FAKE-PROG'.
           
           DISPLAY "Start".
           
           *> Inline comment (Should be ignored)
           CALL 'REAL-PROG'. *> CALL 'FAKE-INLINE'
           
      D    DISPLAY "Debug line".
      
           EXEC SQL
               SELECT * FROM DB_TABLE
           END-EXEC.
           
           STOP RUN.
