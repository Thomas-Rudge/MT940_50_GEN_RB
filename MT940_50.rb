module Mt940_50
  def gen_mt9(source_file, 
              target_file, 
              msg_type='950', 
              dtf='DDMMYYYY',
              # Basic Header Block
              appid='A', 
              servid='21', 
              session_no='0000', 
              seqno='000000',
              # Application Header Block
              drctn='I',
              msg_prty='N',
              dlvt_mnty='',
              obs='',
              inp_time='0000', 
              out_date='010101',
              out_time='1200',
              mir=true,
              # User Header Block
              f113=false,
              mur='MT940950GEN',
              chk=False)
    # CSV --> MT940/50

    # All arguments must be strings.
    #---------------------------------------------------------------
    # active_file : The location of the csv file to be read.
    # msg_type    : Either 940 or 950
    # target_file : The location where the MT940/50 should be written
    #---------------------------------------------------------------

    # Optional Arguments
    # dtf         : The format of the dates present in the csv file - YYYYMMDD
    #                                                                 DDMMYYYY (Default)
    #                                                                 MMDDYYYY
    # {1: Basic Header Block ----------------------------------------
    # appid       : Application ID - A = General Purpose Application
    #                                F = Financial Application
    #                                L = Logins
    # servid      : Service ID - 01 = FIN/GPA
    #                            21 = ACK/NAK
    # session_no  : Session Number
    # seqno       : Sequence Number
    # {2: Application Header Block ----------------------------------
    # drctn       : Direction - I =Input (to swift)
    #                           O = Output (from swift)
    # msg_prty    : Message Priority - S = System
    #                                  N = Normal
    #                                  U = Urgent)
    # dlvt_mnty   : Delivery Monitoring Field - 1 = Non delivery warning
    #               [Input Only]                2 = Delivery notification
    #                                           3 = Both (1 & 2)
    # obs         : Obsolescence period - 003 = 15 minutes (When priority = U)
    #               [Input Only]          020 = 100 minutes (When priority = N)
    # inp_time    : Input Time of Sender - HHMM - [Output Only]
    # out_time    : Output Time from Swift - HHMM - [Output Only]
    # out_date    : Output Date from Swift - YYMMDD - [Output Only]
    # mir         : Message Input Reference - If True MIR is autogenerated, all
    #               [Output Only]             other values will be used as the MIR
    # {3: User Header Block -----------------------------------------
    # f113        : Banking Priority Code - nnnn
    # mur         : Message User Reference
    # {5: Trailer Block ---------------------------------------------
    # chk         : The checksum for the message.
    if source_file and not File.file?(source_file)
      return false
    end
    
    trn = 0
    lst_line = nil
    prev_line = {
      account: '',
      sendbic: '',
      recvbic: '',
      stmtno: '',
      stmtpg: '',
      ccy: '',
      cbalsgn: '',
      cbaltyp: '',
      cbaldte: '',
      cbal: '',
      abalsgn: '',
      abaldte: '',
      abal: ''
    }
           
    CSV.foreach(active_file) do |row|
      line = '' # Value that will eventually appended to file
      # Ignore the header
      if row[-2].upcase().gsub(' ', '') == 'REF4(MT940ONLY)' || row[0] == ''
        next
      # Script should stop if the column count is wrong
      elsif row.length != 27
        raise Exception.new('Bad column count %d : %s' % [row.length, row.to_s])
      end  
      row = convert_values(row, dtf)
      
      # Check to see whether a previous page should be closed.
      if (prev_line[stmtpg] != row[4] or prev_line[account] != row[2]) and prev_line[account] != ''
        # Close the page: ":62F:D151015EUR1618033889"
        line = ':62%s:%s%s%s%s\n' % [prev_line[cbaltyp],
                                     prev_line[cbalsgn],
                                     prev_line[cbaldte],
                                     prev_line[cbalccy],
                                     prev_line[cbal]]
        if prev_line[abalsgn] != ''
          # Write available balance line: ":64:C151015EUR4238,05"
          line += ':64:%s%s%s%s\n' % [prev_line[abalsgn],
                                      prev_line[abaldte],
                                      prev_line[ccy],
                                      prev_line[abal]]
        end
      end
      
      # Check to see whether it's a new message.
      if prev_line[sendbic] != row[0].upcase || prev_line[recvbic] != row[1].upcase
        if prev_line[sendbic] != ''
          # Not the first msg, so the last msg must be closed
          if chk
            line += '-}{5:{CHK:%s}}\n' % chk
          else
            line += '-}{5:}\n'
          end
        end
        # Open the next message
        # Create Basic Header
        line += '{1:%s%s%s%s%s}' % [appid,
                                    servid,
                                    row[0].ljust(12, 'X'),
                                    session_no,
                                    seqno]
        
        # Create Application Header
        if drctn == 'I' # Inward
          line += '{2:I%s%s%s%s%s}' % [msg_type,
                                       row[1].ljust(12, 'X'),
                                       msg_prty,
                                       dlvt_mnty,
                                       obs]
        else #Outward
          if mir == true
            # Auto generate the MIR
            mir = Time.new.to_s.gsub('-','')[2..7] + 
                  row[0].ljust(12,'X') + 
                  session_no + 
                  seqno
          end
          # Add the block
          line += '{2:O%s%s%s%s%s%s}' % [msg_type,
                                         inp_time,
                                         mir,
                                         out_date,
                                         out_time,
                                         msg_prty]
        end
        ## Create field 113 if present
        f113 = !f113 ? '{113:%s}' % f113.to_s.rjust(4, '0') : ''
        line += '{3:%s{118:%s}{4:\n' % [f113, mur]
      end
      # Check to see whether a new page should be opened.
      if prev_line[stmtpg] != row[4] || prev_line[account] != row[2]
        # Add the TRN
        if row[26] == ''
          line += ':20:MT94050GEN%s\n' % trn.to_s.rjust(6,'0')
          trn += 1
        else
          line += ':20:%s\n' % line[26]
        end
        # Add the account number and statement/page numbers
        line += ':25:%s\n%s:28C:%s/%s\n' % [row[2],
                                            row[3].rjust(5, '0'),
                                            row[4].rjust(5, '0')]
        # Add the opening balance
        line += ':60%s:%s%s%s%s\n' % [row[6],
                                      row[5],
                                      row[7],
                                      row[24],
                                      row[8]]                               
      end
      # Now add the item line
      line += ':61:%s%s%s%s%s%s//%s\n' % [row[9],
                                          row[10],
                                          row[11],
                                          row[12],
                                          row[13],
                                          row[14],
                                          row[15]]
      
      # Add item Ref3 if present
      if row[16] != ''
        line += '%s\n' % row[16]
      end
      # Add item Ref4 if present and 940
      if msg_type == '940' && row[25].gsub(' ', '') != ''
        line += ':86:%s\n' % row[25]
      end
      
      append_line_to_file(line, target_file)
      
      prev_line[account] = row[2]
      prev_line[sendbic] = row[0]
      prev_line[recvbic] = row[1]
      prev_line[stmtno]  = row[3]
      prev_line[stmtpg]  = row[4]
      prev_line[ccy]     = row[24]
      prev_line[cbalsgn] = row[17]
      prev_line[cbaltyp] = row[18]
      prev_line[cbaldte] = row[19]
      prev_line[cbal]    = row[20]
      prev_line[abalsgn] = row[21]
      prev_line[abaldte] = row[22]
      prev_line[abal]    = row[23]
      lst_line = row
      
    end ## End of CSV row loop
    
    # Close the last line
    line = ':62F:%s%s%s%s\n' % [lst_line[17],
                                lst_line[19],
                                lst_line[24],
                                lst_line[20]]
    # Add available balance if present (:64:)
    if lst_line[21] != ''
      line += ':64:%s%s%s%s\n' % [lst_line[21],
                                  lst_line[22],
                                  lst_line[24],
                                  lst_line[23]]
    end
    # Add checksum if present
    if chk
      line += '-}{5:{CHK:%s}}' % chk
    else
      line += '-}{5:}'
    end
    # Append the last line to file
    append_line_to_file(line, target_file)
    
    puts 'MT%s created successfully.' % msg_type
    
  end
  
  ## Appends a line to a file
  def append_line_to_file(line, file)
    File.open(file, 'a+') { |file| file.write(line) } end  
  end
  
  ## Converts supplied values to swift MT equivalents for dates, amounts 
  def conver_values(xline, dtf_)
    xline.each_with_index do |val, idx|
      case idx
      when 11, 21, 5, 6, 17, 18
        # Upper case Types and Signs.
        val = val.upcase! || val
      when 8, 12, 20, 23
        # All amounts, remove thousands seps, and replace decimal spot with comma
        val = val.gsub!(/[,-]/, '') || val
        val = val.gsub!('.', ',') || val
      when 7, 9, 10, 19, 22
        # Convert dates to YYMMDD
        if dtf_ == 'DDMMYYYY'
          val = val[8..9] + val[3..4] + val[0..1]
        elsif dtf_ == 'MMDDYYYY'
          val = val[8..9] + val[0..1] + val[3..4]
        else # YYYYMMDD
          val = val[2..3] + val[5..6] + val[8..9]
        end
        when 16, 21, 26
          if !val || val.gsub(' ', '') == ''
            val = ''
          end
      end
    end
    
    return(xline)
  
  end
end