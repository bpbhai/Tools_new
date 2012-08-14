#!/usr/bin/perl -w

use strict ;

################################################################################
#
# P4checkit.pl : script to check results of doing workbook exercise
#
# This script checks how well a user has done in working through the 'workbook'
# exercises.
#
################################################################################

################################################################################
sub Usage{
#
# Show the usage message.
#
################################################################################

    print "\n\n" ;
    print "Usage :\n" ;
    print "  P4checkit.pl [-d|--debug] [-c changesafter] [-w worksheet_depot] username\n" ;
    print "    where\n" ;
    print "      [-d|--debug]         more verbose output\n" ;
    print "      -c changesafter      only changelists after this will be considered\n" ;
    print "      -w worksheet_depot   use specified depot - default is //WORKSHEET\n" ;
    print "      username             name of user for to be checked\n\n" ;
}



# Command line argument handling
use Getopt::Long ;
Getopt::Long::Configure ("bundling") ;

# Perforce API
use P4 ;

# Constants!!
my $WORKSHEET_AREA = "//WORKSHEET" ;

# Globals!! Available everywhere.
my $DEBUG=0 ;

# This copes with the inconsistencies in naming conventions used for the various elements in Perforce
my @ITEMDETAILS = (
	{ item => 'workspace',	items => 'workspaces',	keymatch1 => 'client', keymatch2 => 'Client'	},
	{ item => 'branch',	items => 'branches',	keymatch1 => 'branch', keymatch2 => 'Branch'	},
	{ item => 'label',	items => 'labels',	keymatch1 => 'label',  keymatch2 => 'Label'	},
	{ item => 'change',	items => 'changes',	keymatch1 => 'change', keymatch2 => 'change'	},
    ) ;

my $TESTS=15;

################################################################################
sub LookupItemDetails {
#
# Returns the value for the requested key in the ITEMDETAILS lookup table
#
################################################################################

my ( $item, 		# Item to look up
     $key,		# Required key to look for
   ) = @_ ;

    for my $href ( @ITEMDETAILS ) {
	next if $href->{item} ne $item ;
	return $href->{$key} ;
    }
}


################################################################################
sub catch_warn {
#
#  Signal handler
#
################################################################################

    printf "\nUnknown option" ;
    Usage() ;
    exit 1 ;
}


################################################################################
sub CheckUserExists {
#
# Chaeck that the requested user exists
#
################################################################################

my ($p4, 		# Perforce connection
    $requser, 		# Required user ID
   ) = @_ ;

my $entry ;
my $key ;
my @p4_users = () ;
my $retval = 0 ;

    # Get the list of users
    @p4_users = $p4->RunUsers();

    foreach $entry ( @p4_users ) {
	foreach  $key ( keys %$entry ) {
	    if ( $key eq "User" ) {
		$retval = 1 if $entry->{$key} eq $requser ;			    
	    }
	last if $retval ;
	}
    } 
    return $retval ;
}


################################################################################
sub GetPerforceConnectionDetails {
#
# Looks for Perforce specific environment variables to use.
# If P4CONFIG is set, then use that.
# Otherwise - looks for P4PORT, P4USER and P4PASSWD, prompting the user
# for entry of any that are not set.
#
################################################################################

my ( $p4 ) = @_ ;	# Perforce class

my $answer = "" ;

    if ( ! $ENV{'P4CONFIG'} ) {

	# Use env var P4PORT if set, otherwise prompt user for value.
	if ( $ENV{'P4PORT'} ) {
	    $p4->SetPort($ENV{'P4PORT'}) ;
	    }
	# (port number 1666 is assumed if a port is not supplied)
	else {
	    print "Please enter Perforce_server[:port] : " ;
	    $answer = <STDIN> ;
	    chomp ($answer) ;
	    $answer =~ m/:/ ? $p4->SetPort("$answer") : $p4->SetPort("$answer:1666") ;
	    }

	# Use env var P4USER if set, otherwise prompt user for value.
	if ( $ENV{'P4USER'} ) {
	    $p4->SetUser($ENV{'P4USER'}) ;
	    }
	else {
	    print "Please enter Perforce user name : " ;
	    $answer = <STDIN> ;
	    chomp ($answer) ;
	    $p4->SetUser($answer) ;
	    }

	# Check if user is logged in otherwise prompt for password.
	if (!IsLoggedIn()) {
	    print "Please enter Perforce password : " ;
	    $answer = <STDIN> ;
	    chomp ($answer) ;
	    $p4->SetPassword($answer) ;
	    }
	}
    #print "\n" ;
}

################################################################################
sub IsLoggedIn {
#
# Assumes P4PORT and P4USER have been set
################################################################################
    open(P4_LOGIN, "p4 login -s 2>&1 |") or die "Failed to run 'p4 login -s' command";
    my @out = <P4_LOGIN>;
    close P4_LOGIN;
    return ($out[0]=~/^User.*ticket expires.*/i);
}

################################################################################
sub GetUserItems {
#
# Get the details from Perforce for all the items of the required type for 
# the required user.
#
################################################################################

my ($p4, 		# Perforce connection
    $requser, 		# Required user ID
    $item, 		# Required item type
    $savearr		# Array to hold results
   ) = @_ ;

my $content ;
my $entry ;
my $items ;
my $key ;
my $keymatch ;
my @p4_items = () ;
my @tmparr = () ;

    # Look up the things that are specific to the item being requested
    $items    = LookupItemDetails($item, "items") ;
    $keymatch = LookupItemDetails($item, "keymatch1") ;

    # Get the list of items of the required type for the user
    @p4_items = $p4->Run($items, "-u", $requser);
    foreach $entry ( @p4_items ) {
	foreach  $key ( keys %$entry ) {
	    push @tmparr, $entry->{$key}  if $key eq $keymatch ;
	}
    }
    PrintList(uc($item), @tmparr)  if  $DEBUG >= 3 ;

    # Now find the full details of each item of the required type
    foreach $entry ( sort @tmparr ) {
	$content = $p4->Run($item, "-o", $entry);
	push @$savearr, $content ;
    }
}


################################################################################
sub ShowUserItems {
#
# Debug function - show the details of the required item type for the required user
#
################################################################################

my ($item, 		# Required item type
    @savearr		# Array holding results
   ) = @_ ;

my $entry ;
my $href ;
my $items ;
my $keymatch ;
my $view ;
my $viewitem ;

    # Look up the things that are specific to the item being shown
    $items    = LookupItemDetails($item, "items") ;
    $keymatch = LookupItemDetails($item, "keymatch2") ;

    foreach $entry ( @savearr ) {
	foreach $href ( @$entry ) {
	    printf "==== %s : %s\n", $item, $href->{$keymatch} ;

	    printf "  %-15s => %s\n", "Root",          $href->{Root}           if $href->{Root} ;
	    printf "  %-15s => %s\n", "SubmitOptions", $href->{SubmitOptions}  if $href->{SubmitOptions} ;
	    printf "  %-15s => %s\n", "Options",       $href->{Options}        if $href->{Options} ;

	    $view = $href->{View};
	    print "  View\n";
	    foreach $viewitem ( @$view ) {
		printf "        %s\n", $viewitem ;
	    }
	}
	#print "\n" ;
    }
}

################################################################################
sub GetUserChanges {
#
# Get the details from Perforce for changelists for the required user.
# Results can be constrained by supplying a 'start after' changelist number.
# This may be useful if the user has restarted the workbook.
#
################################################################################

my ($p4, 		# Perforce connection
    $requser, 		# Required user ID
    $chgafter, 		# Consider changelists after this number
    $savearr		# Array to hold results
   ) = @_ ;
   
my $content ;
my $entry ;
my $item = "change" ;
my $items ;
my $key ;
my $keymatch ;
my @p4_items = () ;
my @tmparr = () ;

    $items    = LookupItemDetails($item, "items") ;
    $keymatch = LookupItemDetails($item, "keymatch1") ;

    @p4_items = $p4->Run($items, "-u", $requser);
    foreach $entry ( @p4_items ) {
	foreach  $key ( keys %$entry ) {
	    if ( $key eq $keymatch )  {
		next if $entry->{$key} <=  $chgafter ;
		push @tmparr, $entry->{$key} ;
	    }
	}
    }
    PrintList(uc($item), @tmparr)  if  $DEBUG >= 3 ;

    foreach $entry (sort @tmparr ) {
	$content = $p4->Run("describe", "-s", $entry);
	push @$savearr, $content ;
    }
}

################################################################################
sub ShowUserChanges {
#
# Debug function - show the details of the required item type for the required user
#
################################################################################

my ( @savearr		# Array holding results
   ) = @_ ;
   

my $actions ;
my $entry ;
my $fnames ;
my $href ;
my $idx ;
my $keymatch ;
my $tmpstr = "" ;
my @pendarr = () ;
my @subarr = () ;

    $keymatch = LookupItemDetails("change", "keymatch2") ;
    foreach $entry (@savearr ) {
	foreach $href ( @$entry ) {
	    printf "===== changelist : %d\n", $href->{$keymatch} ;
	    $fnames  = $href->{depotFile} ;
	    $actions = $href->{action} ;
	    for $idx ( 0 .. $#$fnames ) {
		    printf "    %-12s  %s\n", $$actions[$idx], $$fnames[$idx] ;
		}
	    }
	    #print "\n" ;
	}
    }


################################################################################
sub CheckBranchFor {
#
# Check on all expected branch operations
#
################################################################################

my ($branchname,	# Branch name to be checked
    $p4, 		# Perforce connection
    $user, 		# Required user ID
    @chgarr		# Array holding branch specifications
   ) = @_ ;

my $entry ;
my $found ;
my $foundcount = 0 ;
my $href ;
my $keymatch ;
my $branchview ;
my $branch ;
my $lock ;
my $matchsrc ;
my $matchtarg ;
my $pass_create = 0 ;
my $pass_lock = 0 ;
my $pass_sync = 0 ;
my $view ;
my $viewlines ;
my $viewitem ;
my @tmppass = () ;
my @tmpwarn = () ;
my @goodbranches = () ;
my @integrates = () ;

    print "\n=== Checking branching operations ===\n" ;

    $matchsrc = "$WORKSHEET_AREA/$user/mainline/..." ;
    $matchtarg = "$WORKSHEET_AREA/$user/$branchname/..." ;

    $keymatch = LookupItemDetails("branch", "keymatch2") ;
    foreach $entry (@chgarr ) {
	$found = 0 ;
	$viewlines = -1 ;
	$branchview = "" ;
	foreach $href ( @$entry ) {
	    $branch = $href->{$keymatch} ;
	    $lock = $href->{Options} ;
	    $view = $href->{View};
	    $viewlines = $#{$view} + 1 ;
	    foreach $viewitem ( @$view ) {
		if ( $viewitem =~ m/$matchsrc $matchtarg/i ) {
		    $found = 1 ;
		    $branchview = $viewitem ;
		}
	    }
	}

	if ( $found ) {
	    $foundcount++ ;
	    if ( $viewlines == 1 ) {
		push @tmppass, sprintf "PASS\t>>%s<< - has correct view line %s", $branch, $branchview ;
		push @goodbranches, { name => $branch, status => $lock } ;
		$pass_create = 1;
	    }
	    else {
		push @tmpwarn, sprintf "WARN\t>>%s<< - has correct view line, but has %d additional line(s)", $branch, $viewlines - 1  ;
	    }
	}
    }

    print "        === Branch specification ===\n" ;
    if ( $foundcount ) {
	foreach my $tmpstr ( @tmpwarn ) {
	    printf "               === %s\n", $tmpstr ;
	}
	foreach my $tmpstr ( @tmppass ) {
	    printf "               === %s\n", $tmpstr ;
	}
    }
    else {
	print "FAIL\t No suitable branch specification found\n" ;
    }

    print "        === Branch locking ===\n" ;
    if ( $#goodbranches >= 0 ) {
	for $href ( @goodbranches ) {
	    printf "               === PASS\t >>%s<< - is locked\n", $href->{name}  if $href->{status} eq 'locked' ;
	    $pass_lock = 1  if $href->{status} eq 'locked' ;
	    printf "               === FAIL\t >>%s<<  - is unlocked\n", $href->{name} if $href->{status} eq 'unlocked' ;
	}
    }
    else {
        print "FAIL\t 'rel' branch not created\n" ;
    }

    print "        === Branch creation ===\n" ;
    if ( $#goodbranches >= 0 ) {
	for $href ( @goodbranches ) {
	    @integrates = $p4->RunIntegrated("-b", $href->{name}) ;
	    printf "               === PASS\t >>%s<< - used successfully for branch creation\n", $href->{name}  if $#integrates >= 0 ;
	    $pass_sync = 1 if $#integrates >= 0 ;
	    printf "               === FAIL\t >>%s<<  -no branch creation found\n",  $href->{name}  if $#integrates == -1 ;
	}
	if ( $DEBUG >= 1 ) {
	    foreach $entry ( @integrates ) {
		printf "%s - branch from %s\n", $entry->{toFile}, $entry->{fromFile} ;
	    }
	    #print "\n" ;
	}
    }
    else {
	print "FAIL\t 'rel' branch not created\n" ;
    }
    
    return $pass_create + $pass_lock + $pass_sync ;

}
################################################################################
sub CheckLabelFor {
#
# Check on all expected branch operations
#
################################################################################

my ($branchname, 	# Branch name to be checked
    $p4, 		# Perforce connection
    $user, 		# Required user ID
    @chgarr		# Array holding branch specifications
   ) = @_ ;
  

my $entry ;
my $found ;
my $foundcount = 0 ;
my $href ;
my $keymatch ;
my $label ;
my $lock ;
my $pass_create = 0 ;
my $pass_lock = 0 ;
my $pass_sync = 0 ;
my $view ;
my $viewmatch = "" ;
my $viewlines ;
my $viewitem ;
my @tmppass = () ;
my @tmpwarn = () ;
my @goodlabels = () ;
my $haves ;
my $labels ;

    print "\n=== Checking labelling operations ===\n" ;

    $viewmatch = "$WORKSHEET_AREA/$user/$branchname/..." ;

    $keymatch = LookupItemDetails("label", "keymatch2") ;
    foreach $entry (@chgarr ) {
	$found = 0 ;
	$viewlines = -1 ;
	foreach $href ( @$entry ) {
	    $label = $href->{$keymatch} ;
	    $lock = $href->{Options} ;
	    $view = $href->{View};
	    $viewlines = $#{$view} + 1 ;
	    foreach $viewitem ( @$view ) {
		$found = 1 if $viewitem eq $viewmatch ;
	    }
	}

	if ( $found ) {
	    $foundcount++ ;
	    if ( $viewlines == 1 ) {
		push @tmppass, sprintf "PASS\t>>%s<< - has correct view line  %s", $label, $viewmatch  ;
		push @goodlabels, { name => $label, status => $lock } ;
		$pass_create = 1 ;
	    }
	    else {
		push @tmpwarn, sprintf "WARN\t>>%s<< - has correct view line, but has %d additional line(s)", $label, $viewlines - 1  ;
	    }
	}
    }

    print "        === Label creation ===\n" ;
    if ( $foundcount ) {
	foreach my $tmpstr ( @tmpwarn ) {
	    printf "               === %s\n", $tmpstr ;
	}
	foreach my $tmpstr ( @tmppass ) {
	    printf "               === %s\n", $tmpstr ;
	}
    }
    else {
	print "FAIL\t no appropriate label found\n" ;
    }

    print "        === Label locking ===\n" ;
    if ( $#goodlabels >= 0 ) {
	for $href ( @goodlabels ) {
	    printf "               === PASS\t>>%s<< - is locked\n", $href->{name} if $href->{status} eq 'locked' ;
	    $pass_lock = 1 if $href->{status} eq 'locked' ;
	    printf "               === FAIL\t>>%s<< - is unlocked\n", $href->{name} if $href->{status} eq 'unlocked' ;
	}
    }
    else {
	print "FAIL\t no appropriate label found\n" ;
    }

    print "        === Label sync ===\n" ;
    if ( $#goodlabels >= 0 ) {
	for $href ( @goodlabels ) {
	    $labels = "$WORKSHEET_AREA/$user/...\@$href->{name}" ;
	    $pass_sync = CheckLabelledFiles($p4, $href->{name}, $labels, $viewmatch) ;
	}
    }
    else {
	print "FAIL\t no appropriate label found\n" ;
    }
    return $pass_create + $pass_lock + $pass_sync ;
}


################################################################################
sub CheckLabelledFiles {
#
# Check on all expected label operations
#
################################################################################

my ($p4, 
    $label,
    $havelabel, 
    $havefiles
   ) = @_ ;

my @fstat_arr = () ;
my @havelabelarr = () ;
my @havefilearr = () ;
my $pass_sync = 0 ;
my $entry ;
my $key ;
my $x ;
my %counts = () ;
my $status = 1 ;


    @fstat_arr = $p4->RunFstat("-T", "depotFile, haveRev", "-Olp", $havelabel) ;
    foreach $entry ( @fstat_arr ) {
	if ( exists $entry->{haveRev} ) {
	    push @havelabelarr, $entry->{depotFile} ;
	    $counts{$entry->{depotFile}}++  ;
	}
    }

    @fstat_arr = $p4->RunFstat("-T", "depotFile, haveRev", "-Olp", $havefiles) ;
    foreach $entry ( @fstat_arr ) {
	if ( exists $entry->{haveRev} ) {
	    push @havefilearr, $entry->{depotFile} ;
	    $counts{$entry->{depotFile}}++ ;
	}
    }

    foreach $x (keys %counts) {
	last if $counts{$x} != 2  && ($status = 0) ;
    }

    printf "               === %s\t>>%s<< - %s \n", $status ? "PASS" : "FAIL", $label,
				      $status ? "all appropriate files on devel branch are labelled" 
					      : "labelling error" ;
    if ($status) {
    	$pass_sync = 1 ;
    }

    if ( $DEBUG >= 1 ) {
	print "      Workspace files ...\n" ;
	foreach ( @havefilearr ) {
	    printf "%s\n", $_ ;
	}
	print "      Labelled files ...\n" ;
	foreach ( @havelabelarr ) {
	    printf "%s\n", $_ ;
	}
    }
    return $pass_sync ;
}


################################################################################
sub CheckChangesFor {
#
################################################################################

my ($type,
    @chgarr
   ) = @_ ;

my $actions ;
my $entry ;
my $fnames ;
my $href ;
my $idx ;
my $keymatch ;
my $tmpstr = "" ;
my @pendarr = () ;
my @subarr = () ;
my $passcount = 0 ;

    $keymatch = LookupItemDetails("change", "keymatch2") ;
    foreach $entry (@chgarr ) {
	foreach $href ( @$entry ) {
	    $fnames  = $href->{depotFile} ;
	    $actions = $href->{action} ;
	    for $idx ( 0 .. $#$fnames ) {
		if (  $$actions[$idx] eq $type ) {
		    push @subarr,  sprintf("%-25s %6d  :  %s", $href->{client}, $href->{$keymatch} , $$fnames[$idx]) if $href->{status} eq "submitted" ;
		    push @pendarr, sprintf("%-25s %6d  :  %s", $href->{client}, $href->{$keymatch} , $$fnames[$idx]) if $href->{status} eq "pending" ;
		}
	    }
	}
    }
    $tmpstr = sprintf "%-40s", "        === Checking $type operations" ;
    if ( $#subarr >= 0 ) {
	printf "%s\t===\tPASS\t  %4d submitted %s operations found\n", $tmpstr, $#subarr +1, $type ;
        $passcount = 1;
	foreach my $tmpstr ( @subarr ) {
	    printf "      %s\n", $tmpstr  if $DEBUG >= 1 ;
	}
    }
    elsif ( $#subarr == -1  &&  $#pendarr >= 0 ) {
    	printf "WARN\t  %4d pending %s operations found\n", $#pendarr +1, $type ;
	foreach my $tmpstr ( @pendarr ) {
	    printf "      %s\n", $tmpstr if $DEBUG >= 1 ;
	}
    }
    else {
	printf "FAIL\t  0 submitted or pending %s operations found\n", $type ;
    }
    
    return $passcount ;
}

################################################################################
sub CheckJobsFor {
#
################################################################################

my (
    @chgarr
   ) = @_ ;

my $entry ;
my $href ;
my $passcount = 0 ;
    
    foreach $entry (@chgarr ) {
	foreach $href ( @$entry ) {
	    if (defined $href->{job}) {
	    	foreach (@{$href->{job}}){
	    	    $passcount++  if ($_=~/WB_TRAINING_JOB/);
		}
	    }
        }
    }
    
    my $tmpstr = sprintf "%-40s", "        === Checking job operations" ;
    if ( $passcount> 0 ) {
	printf "%s\t===\nPASS\t  %4d job operations found\n", $tmpstr, $passcount;
    }
    else {
	printf "%s\t===\nFAIL\t  %4d job operations found\n", $tmpstr, $passcount;
    }
    
    return (1?$passcount>0:0);
}

################################################################################
sub PrintList {
#
################################################################################

my ($type, 
    @arr
   ) = @_ ;

    printf "%s list\n", $type ;
    foreach my $item ( sort @arr ) {
	printf("  %-15s : %s\n", $type, $item) ;
    }
    print "\n" ;
}


################################################################################
sub CheckUserPassword {
#
################################################################################

my ($p4, 
    $p4user
   ) =@_ ;

my $adminuser ;
my $user ;
my $password ;
my $passcount = 0 ;

    print "\n=== Checking password operations ===\t" ;
    $adminuser = $p4->GetUser() ;

    $p4->SetUser($p4user) ;
    $p4->RunPasswd("-O","password","-P","password") ;

    ## The check is deliberately the wrong way round.!!
    ## If this attempt to change the user password fails, then they have
    ## changed it themseleves successfully.
    if ( $p4->ErrorCount() ) {
	print "\nPASS\t password has been reset\n" ;
     	$passcount = 1;
    }
    else {
	print "\nFAIL\t password has not been reset\n" ;
    }

    $p4->SetUser($adminuser) ;
    $adminuser = $p4->GetUser() ;
    
    return $passcount ;
}


################################################################################
sub CheckWorkspaceFor {
#
#
################################################################################

my ($branch,
    $user,
    @warr
   ) = @_ ;

my $entry ;
my $workspace ;
my $href ;
my $foundcount = 0 ;
my $items ;
my $keymatch ;
my $view ;
my $viewlines ;
my $viewitem ;
my $matchdepot1 ;
my $matchdepot2 ;
my $matchws1 ;
my $matchws2 ;
my $match1 ;
my $match2 ;
my $passcount = 0 ;
my @tmppass = () ;
my @tmpwarn = () ;

    $keymatch = LookupItemDetails("workspace", "keymatch2") ;

    printf "        === Workspace for mainline and %s\n", $branch ;

    $matchdepot1 = "$WORKSHEET_AREA/$user/mainline/..." ;
    $matchdepot2 = "$WORKSHEET_AREA/$user/$branch/..." ;

    foreach $entry ( @warr ) {
	$match1 = $match2 = 0 ;
	foreach $href ( @$entry ) {
	    $workspace = $href->{$keymatch} ;
	    #
	    # Match needs to have target branch IMMEDIATELY following workspace root
	    #         or have any number of intermediate directories in between
	    # This maps to  >>//root/<<  followed by     nothing at all     followed by >>branch/...<<
	    #           or  >>//root/<<  followed by  >>any/dir/paths/<<    followed by >>branch/...<<
	    # Note >>any/dir/paths/<< MUST end with a / but not begin with a /
	    #
	    $matchws1 = "//$workspace/([^/].*/|)mainline/..." ;
	    $matchws2 = "//$workspace/([^/].*/|)$branch/..." ;
	    printf "%s >> >>%s %s<<\n", $workspace, $matchdepot1, $matchws1 if $DEBUG >= 4 ;
	    printf "%s >> >>%s %s<<\n", $workspace, $matchdepot2, $matchws2 if $DEBUG >= 4 ;
	    $view = $href->{View};
	    $viewlines = $#$view + 1 ;
	    foreach $viewitem ( @$view ) {
		$match1 = 1 if $viewitem =~m/$matchdepot1 $matchws1/i ;
		$match2 = 1 if $viewitem =~m/$matchdepot2 $matchws2/i ;
	    }
	    if ( $match1 == 1 && $match2 == 1 ) {
	        $foundcount++ ;
	        $passcount = 1;
		if ( $viewlines == 2 ) {
		    push @tmppass, sprintf "PASS\t>>%s<< - has correct view mapping", $workspace ;
		}
		else {
		    push @tmpwarn, sprintf "WARN\t>>%s<< - has correct view mapping, but %d additional line(s)", $workspace, $viewlines - 2 ;
		}
	    }
	}
    }

    if ( $foundcount ) {
	foreach ( @tmpwarn ) {
	    printf "               === %s\n", $_ ;
	}
	foreach ( @tmppass ) {
	    printf "               === %s\n", $_ ;
	    if ( $DEBUG >= 1 ) {
		m/^.*>>(.*)<</ ;
		$workspace = $1 ;
		foreach $entry ( @warr ) {
		    foreach $href ( @$entry ) {
			if ( $workspace eq $href->{$keymatch} ) {
			    $view = $href->{View};
			    foreach ( @$view ) {
				printf "%s\n", $_ ;
			    }
			}
		    }
		}
	    }
	}
    }
    else {
	print "FAIL\t No suitable workspace specification found\n" ;
    }
    
    return $passcount
}

################################################################################
#
# ENTRY POINT
#
################################################################################
&main() ;

sub main() {

my $p4 = new P4;
my $p4user = "" ;
my $chgafter=1 ;
my $status = 0 ;
my $passes ;

my @workspaces = () ;
my @labels = () ;
my @branches = () ;
my @changes = () ;

    ##$SIG{__WARN__} = \&catch_warn ;

    $p4->Tagged ( 1 ) ;

    GetPerforceConnectionDetails($p4) ;
    $p4->Connect()  
	or die ("Failed to connect to Perforce Server.\nCheck Perforce details and/or Perforce environment variables\n" ) ;

    GetOptions(
        "c:i"		=> \$chgafter,
        "change:i"	=> \$chgafter,
        "d:i"		=> \$DEBUG,
        "debug:i"	=> \$DEBUG,
        "w:s"		=> \$WORKSHEET_AREA,
    ) ;

    if ( $#ARGV != 0 ) {
	$p4->Disconnect();
	Usage() ;
	die ("No user name supplied\n" ) ;
    }
    else {
        $p4user = $ARGV[0] ;
    }

    printf "Perforce check script for user : %s\n", $p4user ;

    eval { 
        $status = CheckUserExists($p4, $p4user) ;
    } ; die "Unknown user" if ! $status ;

    GetUserItems ($p4, $p4user, "workspace", \@workspaces) ;
    GetUserItems ($p4, $p4user, "label",     \@labels) ;
    GetUserItems ($p4, $p4user, "branch",    \@branches) ;

    GetUserChanges ($p4, $p4user, $chgafter, \@changes) ;

    ShowUserItems ("workspace", @workspaces)  if $DEBUG >= 2 ; 
    ShowUserItems ("label",     @labels)      if $DEBUG >= 2 ;
    ShowUserItems ("branch",    @branches)    if $DEBUG >= 2 ;

    ShowUserChanges (@changes)                if $DEBUG >= 2 ;

    print "\n=== Checking file operations ===\n" ;
    $passes += CheckChangesFor("edit",      @changes) ;
    $passes += CheckChangesFor("add",       @changes) ;
    $passes += CheckChangesFor("delete",    @changes) ;
    $passes += CheckChangesFor("branch",    @changes) ;
    $passes += CheckChangesFor("integrate", @changes) ;
    $passes += CheckJobsFor(@changes) ;
    
    print "\n=== Checking workspace specifications ===\n" ;
    $passes += CheckWorkspaceFor("devel",  $p4user, @workspaces) ;
    $passes += CheckWorkspaceFor("rel",    $p4user, @workspaces) ;

    $passes += CheckLabelFor("devel", $p4, $p4user, @labels) ;

    $passes += CheckBranchFor("rel", $p4, $p4user, @branches) ;

    $passes += CheckUserPassword($p4, $p4user) ;

    $p4->Disconnect();

    printf "\nPass rate for %s\t %3.0f %s\n", $p4user, 100*($passes/$TESTS), "\%";
}
