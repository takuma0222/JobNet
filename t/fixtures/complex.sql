-- Test PL/SQL Script

/*
  Block comment section
  EXECUTE FAKE_PROC;
  SELECT * FROM FAKE_TABLE;
*/

CREATE OR REPLACE PROCEDURE TEST_PROC IS
  v_msg VARCHAR2(100);
BEGIN
  -- 1. Normal Call (Mixed Case)
  Pkg_Util.Log_Start();
  
  -- 2. String Literal (Should be ignored)
  v_msg := 'SELECT * FROM SECRET_TABLE';
  DBMS_OUTPUT.PUT_LINE('EXECUTE DANGEROUS_PROC');

  -- 3. DB Operations
  INSERT INTO EMP_TABLE VALUES (1, 'Test');
  
  UPDATE
    DEPT_TABLE
  SET
    NAME = 'IT';
    
  -- 4. Dynamic SQL (Warning)
  EXECUTE IMMEDIATE 'DELETE FROM ' || v_table;
  
  -- 5. File I/O
  f_handle := UTL_FILE.FOPEN('LOG_DIR', 'app.log', 'w');
END;
/
