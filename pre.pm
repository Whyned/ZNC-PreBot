##
# PreBot module for ZNC IRC Bouncer
# Author: m4luc0
# Version: 1.0
## #

package pre;
use base 'ZNC::Module';

use POE::Component::IRC::Common; # Needed for stripping message colors and formatting
use DBI;                         # Needed for DB connection
use experimental 'smartmatch';   # Smartmatch (Regex) support for newer perl versions

use File::Basename;
use Config::IniFiles;


# Some hardcoded settings, however you can overwrite them in your settings.ini
my %STATUS_COLORS = ("NUKE" => 4, "MODNUKE" => 4, "UNNUKE" => 5, "DELPRE" => 5, "UNDELPRE" => 5);
my %STATUS_TYPES = ( "NUKE" => 1, "MODNUKE" => 1, "UNNUKE" => 2, "DELPRE" => 3, "UNDELPRE" => 4);

my %WHITELIST;

# Load config
loadConfig(dirname(__FILE__) . "/settings.ini");


# Module only accessible for users.
# Comment the next line if you want to make it global accessible
#sub module_types { $ZNC::CModInfo::UserModule }

# Module description
sub description {
    "PreBot Perl module for ZNC"
}

# On channel message
sub OnChanMsg {
    # get message informations
    my $self = shift;
    my ($nick, $chan, $message) = @_;

    # Check if user/chan is allowed to feed us
    if(!isAllowed($chan->GetName(), $nick->GetNick())){
      print "#### ".$chan->GetName()." ".$nick->GetNick()." not in Whitelist\n";
      return $ZNC::CONTINUE;
    }

    # Strip colors and formatting
    if (POE::Component::IRC::Common::has_color($message)) {
        $message = POE::Component::IRC::Common::strip_color($message);
    }
    if (POE::Component::IRC::Common::has_formatting($message)) {
        $message = POE::Component::IRC::Common::strip_formatting($message);
    }
    # DEBUG -> everything is working till here so go on and send me the message
    # $self->PutModule("[".$chan->GetName."] <".$nick->GetNick."> ".$message);

    # Split message into words (without dash)
    my @splitted_message = split / /, $message;

    # Check if message starts with a "!""
    my $match = substr($splitted_message[0], 0, 1) eq "!";

    if($match){
        # Get the type (it's the command), uppercased!
        $type = uc(substr($splitted_message[0], 1));
        # Compare different types of announces,
        # assuming that there are common types like pre, (mod)nuke, unnuke, delpre, undelpre

        # ADDPRE / SITEPRE
        if ($type eq "ADDPRE" || $type eq "SITEPRE") {
              # Regex works for a lot of prechans but not for all.
              # Maybe you have to change this.
              # Order: ADDPRE/SITEPRE RELEASE SECTION

              #Pretime is now
              my $pretime = time();

              my $release = $splitted_message[1];
              my $section = $splitted_message[2];


              my $group = getGroupFromRelease($release);

              # DEBUG -> are all the matches correct?
              $self->PutModule($type.": ".$section." > ".$release." - ".$group);

              # Add Pre
              $self->addPre($pretime, $release, $section, $group);
              # Announce Pre
              $self->announcePre($release, $section);

        # ADDOLD
        } elsif ($type eq "ADDOLD") {
              my $release = returnEmptyIfDash($splitted_message[1]);
              my $section = returnEmptyIfDash($splitted_message[2]);
              my $pretime = returnEmptyIfDash($splitted_message[3]);
              my $files   = returnEmptyIfDash($splitted_message[4]);
              my $size    = returnEmptyIfDash($splitted_message[5]);
              my $genre   = returnEmptyIfDash($splitted_message[6]);
              my $reason  = returnEmptyIfDash($splitted_message[7]);
              my $network = returnEmptyIfDash(join(' ',  splice(@splitted_message, 7))); # network contains maybe whitespaces, so we want everything to the end

              my $group = getGroupFromRelease($release);

              print "\nxxx$release\n";

              # DEBUG -> are all the matches correct?
              $self->PutModule("$type : $section - $release - $group - $pretime - $size - $files - $genre - $reason - $network");

              # Add Pre
              $self->addPre($pretime, $release, $section, $group);

              # Add Info
              $self->addInfo($release, $files, $size);

              # Add genre
              $self->addGenre($release, $genre);

              # Add nuke
              $self->changeStatus($release, $STATUS_TYPES{NUKE}, $reason, $network);

              # Announce (we handle it like a pre, maybe you want to do it differently)
              $self->announceAddOld($release, $section, $pretime, $size, $files, $genre, $reason, $network);

        # INFO
        } elsif ($type eq "INFO") {
              # Order: INFO RELEASE FILES SIZE

              my $release = $splitted_message[1];
              my $files = $splitted_message[2];
        	    $files =~ s/F//g;
              my $size = $splitted_message[3];
        	    $size =~ s/MB//g;

              # DEBUG -> are all the matches correct?
              $self->PutModule($type. " release: ".$release." files: ".$files." - size:".$size);

              # Add Info
              $self->addInfo($release, $files, $size);

              # Announce
              $self->announceInfo($release, $files, $size);

        # GENRE/ADDURL/ADDMP3INFO/ADDVIDEOINFO
        } elsif ($type ~~ ["GENRE", "ADDURL", "ADDMP3INFO", "ADDVIDEOINFO"]) {
              my $release = $splitted_message[1];
              my $addinfo  =  join(' ',  splice(@splitted_message, 2));
              # DEBUG -> are all the matches correct?
              $self->PutModule($type. " release: ".$release." info: ".$addinfo);

              if($type eq "GENRE"){
                $self->addGenre($release, $addinfo);
                $self->announceGenre($release, $addinfo);
              }elsif($type eq "ADDURL"){
                $self->addUrl($release, $addinfo);
                $self->announceAddUrl($release, $addinfo);
              }elsif($type eq "ADDMP3INFO"){
                $self->addMp3info($release, $addinfo);
                $self->announceAddMp3Info($release, $addinfo);
              }elsif($type eq "ADDVIDEOINFO"){
                $self->addVideoinfo($release, $addinfo);
                $self->announceAddVideoInfo($release, $addinfo);
              }
        # NUKE/MODNUKE/UNNUKE/DELPRE/UNDELPRE (Status Change)
        } elsif (exists $STATUS_TYPES{$type}) {
              # Order: NUKE RELEASE REASON NUKENET

              my $release = $splitted_message[1];
              my $reason = $splitted_message[2];
              my $network = $splitted_message[3];

              my $status = $STATUS_TYPES{$type};

              # DEBUG -> are all the matches correct?
              $self->PutModule("tpye" . $type.":".$release." - ".$reason." network:".$network);
              # Nuke
              $self->changeStatus($release, $status, $reason, $network);

              # Announce Nuke
    	        $self->announceStatusChange($release, $type, $reason, $network);

        }
    }
    return $ZNC::CONTINUE;
}
##
# PreBot functions
##
# Add Pre
# Params (pretime, release, section, group)
sub addPre {
    my $self = shift;
    # get attribute values
    my ($pretime, $release, $section, $group) = @_;
    # DEBUG -> check if the variables are correct
    # $self->PutModule("Time: ".$pretime." - RLS: ".$release." - Section: ".$section." - Group: ".$group);
    # Connect to Database
    my $dbh = $self->getDBI();

    # Set Query -> Add release
    my $query = "INSERT INTO ".$DB_TABLE." (`".$COL_PRETIME."`, `".$COL_RELEASE."`, `".$COL_SECTION."`, `".$COL_GROUP."`) VALUES( ?, ?, ?, ? );";
    # Execute Query
    $dbh->do($query, undef, $pretime, $release, $section, $group) or die $dbh->errstr;

    # Disconnect Database
    $dbh->disconnect();

}
# Info
# Params (release, files, size)
sub addInfo {
    my $self = shift;

    # get attribute values
    my ($release, $files, $size) = @_;
    # DEBUG -> check if the variables are correct
    # $self->PutModule(.$release." - Files: ".$files." - Size: ".$size);
    # Connect to Database
    my $dbh = $self->getDBI();

    # Set Query -> Add Release Info
    my $query = "UPDATE ".$DB_TABLE." SET `".$COL_FILES."` = ? , `".$COL_SIZE."` = ? WHERE `".$COL_RELEASE."` LIKE ? ;";
    # Execute Query
    $dbh->do($query, undef, $files, $size, $release) or die $dbh->errstr;
    # Disconnect Database
    $dbh->disconnect();
}

# Genre
# Params (release, genre)
sub addGenre {
    my $self = shift;

    # get attribute values
    my ($release, $genre) = @_;
    # DEBUG -> check if the variables are correct
    # $self->PutModule(.$release." - Files: ".$files." - Size: ".$size);
    # Connect to Database
    my $dbh = $self->getDBI();

    # Set Query -> Add Release Info
    my $query = "UPDATE ".$DB_TABLE." SET `".$COL_GENRE."` = ? WHERE `".$COL_RELEASE."` LIKE ? ;";
    print "\nzzz$query\n";
    # Execute Query
    $dbh->do($query, undef, $genre, $release) or die $dbh->errstr;
    # Disconnect Database
    $dbh->disconnect();
}
# Url
# Params (release, url)
sub addUrl {
    my $self = shift;

    # get attribute values
    my ($release, $url) = @_;
    # DEBUG -> check if the variables are correct
    # $self->PutModule(.$release." - Files: ".$files." - Size: ".$size);
    # Connect to Database
    my $dbh = $self->getDBI();

    # Set Query -> Add Release Info
    my $query = "UPDATE ".$DB_TABLE." SET `".$COL_URL."` = ? WHERE `".$COL_RELEASE."` LIKE ? ;";
    print "\nzzz$query\n";
    # Execute Query
    $dbh->do($query, undef, $url, $release) or die $dbh->errstr;
    # Disconnect Database
    $dbh->disconnect();
}

# Mp3info
# Params (release, mp3info)
sub addMp3info {
    my $self = shift;

    # get attribute values
    my ($release, $mp3info) = @_;
    # DEBUG -> check if the variables are correct
    # $self->PutModule(.$release." - Files: ".$files." - Size: ".$size);
    # Connect to Database
    my $dbh = $self->getDBI();

    # Set Query -> Add Release Info
    my $query = "UPDATE ".$DB_TABLE." SET `".$COL_MP3INFO."` = ? WHERE `".$COL_RELEASE."` LIKE ? ;";
    print "\nzzz$query\n";
    # Execute Query
    $dbh->do($query, undef, $mp3info, $release) or die $dbh->errstr;
    # Disconnect Database
    $dbh->disconnect();
}

# Videoinfo
# Params (release, mp3info)
sub addVideoinfo {
    my $self = shift;

    # get attribute values
    my ($release, $videoinfo) = @_;
    # DEBUG -> check if the variables are correct
    # $self->PutModule(.$release." - Files: ".$files." - Size: ".$size);
    # Connect to Database
    my $dbh = $self->getDBI();

    # Set Query -> Add Release Info
    my $query = "UPDATE ".$DB_TABLE." SET `".$COL_VIDEOINFO."` = ? WHERE `".$COL_RELEASE."` LIKE ? ;";
    print "\nzzz$query\n";
    # Execute Query
    $dbh->do($query, undef, $videoinfo, $release) or die $dbh->errstr;
    # Disconnect Database
    $dbh->disconnect();
}

# Nuke, Unnuke, Delpre, Undelpre
# Params (release, status, reason, network)
sub changeStatus {
    my $self = shift;
    # get attribute values
    my ($release, $status, $reason , $network) = @_;
    # DEBUG -> check if the variables are correct
    #$self->PutModule("Type: " .$type." - Release: ".$release." - Reason: ".$reason);

    my $type = $self->statusToType($status);
    $self->PutModule("$type $release - Reason: $reason ($network)");

    # Connect to Database
    my $dbh = $self->getDBI();

    # Set Query -> Change release status
    # 0:pre; 1:nuked; 2:unnuked; 3:delpred; 4:undelpred;
    my $query = "UPDATE ".$DB_TABLE." SET `".$COL_STATUS."` = ? , `".$COL_REASON."` = ?, `".$COL_NETWORK."` = ? WHERE `".$COL_RELEASE."` LIKE ?;";

    #$self->PutModule($query);
    # Execute Query
    $dbh->do($query, undef, $status, $reason, $network, $release) or die $dbh->errstr;

    #debug mysql
    #($sql_update_result) = $dbh->fetchrow;
    #$self->PutModule("WHAT: " . $sql_update_result);
    # Disconnect Database
    $dbh->disconnect();
}


# Returns empty string if $1 is a dash ("-")
# Params: (string)
sub returnEmptyIfDash {
  $str = shift;
  print "$str\n";
  if($str eq "-"){
    return "";
  }

  return $str;
}

# Get a database connection
sub getDBI {
  my $dbi = DBI->connect("DBI:mysql:database=$DB_NAME;host=$DB_HOST", $DB_USER, $DB_PASSWD) or die "Couldn't connect to database: " . DBI->errstr;
  return $dbi;
}

# Extract the groupname of a release/dirname
# Params: (release)
sub getGroupFromRelease {
  my $release = shift;
  return substr($release, rindex($release, "-")+1);
}

# Send a message to announce channel
# Params: (message)
sub sendAnnounceMessage {
  my $self = shift;
  my $message = shift;
  $self->GetUser->FindNetwork($ANNOUNCE_NETWORK)->PutIRC("PRIVMSG ".$ANNOUNCE_CHANNEL." :".$message);
}

# Convert Status (integer) to String (type)
# Params: (status)
# Return: Type (String)
sub statusToType {
  my $status = shift;
  my %rstatus_types = reverse %STATUS_TYPES;
  return $rstatus_types{$status};
}

# Convert Status (integer) to String (type)
# Params: (status)
# Return: Type (String)
sub typeToStatus {
  my $type = shift;
  return $STATUS_TYPES{$type};
}

###
# ANNNOUNCE SUBS
###


#announce a pre
# Params: (release, section)
sub announcePre {
  my $self = shift;
  my ($release, $section) = @_;
  $self->sendAnnounceMessage("7[9PRE7] 7[10$section7] 08- $release");

}

#announce a old pre (currently we just do a announcePre, but maybe we want to do more?)
# Params: (release, section, pretime, size, files, genre, reason, network)
sub announceAddOld {
  my $self = shift;
  my ($release, $section, $pretime, $size, $files, $genre, $reason, $network) = @_;
  $self->announcePre($release, $section);
}

#announce a status Change
# Params: (release, status, reason, network)
sub announceStatusChange {
  my $self = shift;
  my ($release, $type, $reason, $network) = @_;
  my $color = $STATUS_COLORS{$type};
  print "xxxxxx".$color;
  $self->sendAnnounceMessage("7[".$color.$type."7] 08- $release 08- 7[6$reason7] 08- 7[12$network7]");
}

# announce info, in the moment we do nothing, but maybe you want to do something?
# Params: (release, files, size)
sub announceInfo {
  return; # Uncomment if you want to do stuff with this
  my $self = shift;
  my ($release, $files, $size) = @_;

}

# announce genre, in the moment we do nuffin
# Params: (release, genre)
sub announceGenre {
  return; # Uncomment if you want to do stuff with this
  my $self = shift;
  my ($release, $genre) = @_;
}

# announce addurl, in the moment we do nuffin
# Params: (release, url)
sub announceAddUrl {
  return; # Uncomment if you want to do stuff with this
  my $self = shift;
  my ($release, $url) = @_;
}
# announce addmp3info, in the moment we do nuffin
# Params: (release, mp3info)
sub announceAddMp3Info {
  return; # Uncomment if you want to do stuff with this
  my $self = shift;
  my ($release, $mp3info) = @_;
}

# announce addvideoinfo, in the moment we do nuffin
# Params: (release, videoinfo)
sub announceAddVideoInfo {
  return; # Uncomment if you want to do stuff with this
  my $self = shift;
  my ($release, $videoinfo) = @_;
}

# Load Config Ini file and set variables we need
# Params (absolute_filepath)
# dirname(__FILE__) . "/settings.ini"
sub loadConfig {
  my $absolute_filepath = shift;
  my $cfg = Config::IniFiles->new( -file =>  $absolute_filepath);

  our $DB_NAME = $cfg->val( 'settings', 'DB_NAME' );
  our $DB_TABLE = $cfg->val( 'settings', 'DB_TABLE' );
  our $DB_HOST = $cfg->val( 'settings', 'DB_HOST' );
  our $DB_USER = $cfg->val( 'settings', 'DB_USER' );
  our $DB_PASSWD = $cfg->val( 'settings', 'DB_PASSWD' );

  our $COL_PRETIME = $cfg->val( 'settings', 'COL_PRETIME' );
  our $COL_RELEASE = $cfg->val( 'settings', 'COL_RELEASE' );
  our $COL_SECTION = $cfg->val( 'settings', 'COL_SECTION' );
  our $COL_FILES = $cfg->val( 'settings', 'COL_FILES' );
  our $COL_SIZE = $cfg->val( 'settings', 'COL_SIZE' );
  our $COL_STATUS = $cfg->val( 'settings', 'COL_STATUS' );
  our $COL_REASON = $cfg->val( 'settings', 'COL_REASON' );
  our $COL_NETWORK = $cfg->val( 'settings', 'COL_NETWORK' );
  our $COL_GROUP = $cfg->val( 'settings', 'COL_GROUP' );
  our $COL_GENRE = $cfg->val( 'settings', 'COL_GENRE' );
  our $COL_URL = $cfg->val( 'settings', 'COL_URL' );
  our $COL_MP3INFO = $cfg->val( 'settings', 'COL_MP3INFO' );
  our $COL_VIDEOINFO = $cfg->val( 'settings', 'COL_VIDEOINFO' );
  our $ANNOUNCE_NETWORK = $cfg->val( 'settings', 'ANNOUNCE_NETWORK' );
  our $ANNOUNCE_CHANNEL = $cfg->val( 'settings', 'ANNOUNCE_CHANNEL' );

  if($cfg->exists('settings', 'STATUS_COLORS')){
    %STATUS_COLORS = $cfg->val( 'settings', 'STATUS_COLORS' );
  }
  if($cfg->exists('settings', 'STATUS_TYPES')){
    %STATUS_TYPES = $cfg->val( 'settings', 'STATUS_TYPES' );
  }


  if($cfg->SectionExists('whitelist-bot')){
    foreach($cfg->Parameters('whitelist-bot')){
      $channel = lc($_);
      @users = split(/\s*,\s*/, lc($cfg->val('whitelist-bot', $channel)));
      $WHITELIST{$channel} = [@users];
    }
  }
  print "[PREBot] Loaded Config from ".$absolute_filepath."\n";
}

# Check if user/channel are in $WHITELIST
# Params: (channel, user)
sub isAllowed {
  #my $self = shift;
  my ($channel, $user) = @_;
  $channel = lc($channel);
  $user = lc($user);
  # Delete starting #
  if(substr($channel, 0, 1) eq "#"){
    $channel = substr($channel, 1);
  }
  if(!%WHITELIST || (exists $WHITELIST{$channel} && $user ~~ $WHITELIST{$channel})){
    return 1;
  }
  return 0;
}

1;
