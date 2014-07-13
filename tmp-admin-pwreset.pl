#!/usr/bin/perl
#
# 
# tmp-admin-pwreset.pl
#
# -------------------------------------------------------------- #
#
# 
# This script temporarily resets user UNIX and Samba password
#
#
# -------------------------------------------------------------- #





#-----------------------------------------------------------#
#           ---     DOCUMENTATION SECTION      ---          #
#-----------------------------------------------------------#
#

=pod

=head1 NAME

tmp-admin-pwreset.pl - temporary administrative password reset tool

=head1 USAGE

./tmp-admin-pwreset.pl [USERNAME1,USERNAME2,@GROUP1... TEMP_PASSWORD|--restore|--help]


=head1 REQUIREMENTS

=over 1

=item * Samba3 with tdbsam backend

=item * shadow passwords

=item * perl

=item * Programs:

=over 4

=item tdbtool

=item tdbdump

=item chpasswd

=item smbpasswd

=item usermod

=item date

=item cat

=back

=back

=head1 DESCRIPTION

Temporarily resets UNIX and Samba passwords for administrative purposes. The script saves the original password hashes in a file (specified by $current_pw_hashes_db) to allow them to be reset to their original values later. This is useful for administrators who need to login I<as> users, but do not have their passwords. The administrator can unobtrusively login and work on a user account without the user having to change their password back later, or even knowing anything happened. 

While passwords are in a temporarily reset state, the data is stored in the $current_pw_hashes_db file. Before modifying the user databases, the script backs up both user password database files (shadow file and passdb.tdb) to the directory specified by $pw_hashes_backup_dir with a timestamp in the filenames. All these files are protected by mode 0400, but its safe to go back and delete them later on (the backups are made just for safety reasons).


=head1 EXAMPLES

 ./tmp-admin-pwreset.pl jsmith pass
	temporarily resets the password of user jsmith to 'pass'
  
 ./tmp-admin-pwreset.pl jsmith,lwatkins,foo apple
	temporarily resets the password of users jsmith, lwatkins, 
	and foo to 'apple'
  
 ./tmp-admin-pwreset.pl jsmith,@domain-users apple
	temporarily resets the password of user jsmith, and all the 
	users in the group 'domain-users' to 'apple'
  
 ./tmp-admin-pwreset.pl --restore
	restores the passwords for all users whose passwords have been
	temporarily reset.
	
 ./tmp-admin-pwreset.pl --help
	Displays this perldoc page


=head1 Original Mailing List Post

This script was originally released open-source via post to the Samba
mailing list:

 From: Henry Van Styn <vanstyn at intellitree.com>
 Date: Wed Apr 30 21:44:00 GMT 2008
 Subject: [Samba] tmp-admin-pwreset.pl - temporary administrative password reset tool

 I have written a Samba administrative perl script that I wanted to 
 share with the community.

 We use Samba3 with a tdbsam backend (set to be synchronized with the 
 UNIX password database). Our users are Windows XP clients with 
 roaming profiles. During the course of supporting our users, our 
 techs frequently need to login *as* specific users to work on their 
 windows profile, such as Outlook profile settings, check out their 
 user specific problem reports, etc. The trouble is that if we don't 
 know their password (which we don't generally want to know) we have 
 to change their password, and then somehow alert them to the new 
 password so that they can login and reset their password when they 
 get back to their PC after we've worked on it.
 
 This has been a cumbersome problem for us for a while, and to solve 
 it, I finally wrote tmp-admin-pwreset.pl. What it does is simple: 
 you pass it a list of usernames and a temporary password. It will 
 reset the password of all the supplied users (Samba and UNIX) to the 
 temporary password, but first will backup the current password 
 *hashes* for each of the users to a file, so that they can be reset 
 to their original values later on. You then call the script in 
 another mode ("--restore") and it sets all the password hashes for 
 both UNIX and Samba to what they were originally.
 
 This effectively allows administrators to be able login as specific 
 users without knowing their password, and without having to change 
 their password either. Users won't even know anything changed at all 
 (and won't call the helpdesk because they can't login; didn't see 
 the note, didn't listen to the voicemail, etc).
 
 I wrote this for our own use, however, I thought it might be useful 
 to others, so I am sharing it.
 
 If anyone is interested, the script and documentation can be 
 downloaded here:
 
 http://devzone.intellitree.com/projects/tmp-admin-pwreset
 
 Best regards,
 
 Henry Van Styn
 IntelliTree Solutions llc
 http://www.intellitree.com


=head1 CHANGELOG

=over 1

=item 2008-04-30
Version 0.1 
Initial program development

=back


=head1 COPYRIGHT

Copyright (c) 2008 IntelliTree Solutions llc (http://www.intellitree.com)

Permission is granted to copy, distribute and/or modify this program under the terms of the GNU Free Documentation License, Version 1.2 or any later version published by the Free Software Foundation; with no Invariant Sections, with no Front-Cover Texts, and with no Back-Cover Texts.

If you modify and/or redistribute the script, please preserve orignal author and documentation information.


=head1 WARRANTY

This script is free software and comes with B<absolutely no warranty whatsoever>, use at your own risk. The author, and IntelliTree Solutions in general, have no liability for any damage or data loss that may be caused by using this software.


=head1 AUTHOR

 Henry Van Styn <vanstyn@intellitree.com>
 IntelliTree Solutions llc (http://www.intellitree.com)

=cut


#-----------------------------------------------------------#
#                 ---    USE SECTION    ---                 #
#-----------------------------------------------------------#
#


use strict;
use lib '/opt/sbl/scripts/include';



#-----------------------------------------------------------#
#           ---    GLOBAL VARIABLES SECTION    ---          #
#-----------------------------------------------------------#
#



	my $VERSION = "0.1";
	my $SCRIPT_NAME = 'tmp-admin-pwreset.pl';
	
	my @needed_programs = (
		'tdbdump',
		'tdbtool',
		'chpasswd',
		'smbpasswd',
		'usermod',
		'cat',
		'date'
	);
	
	my $current_pw_hashes_db = '/opt/site/var/.current-pw_hashes.db';
	my $pw_hashes_backup_dir = '/opt/site/var/pw_hashes-backups/';
	
	my $passdb_file = '/etc/samba/passdb.tdb';
	my $shadow_file = '/etc/shadow';
	my $group_file = '/etc/group';
	
	
	my ($current_pw_hashes_db_data,$username_string_list,$db_date_time);
	my @shadow_entries;
	my @tdbdump_entries;
	my @group_lines;
	my @usernames_to_set;

	
	
	
#-----------------------------------------------------------#
#               ---    MAIN CODE SECTION    ---             #
#-----------------------------------------------------------#
#

&display_perldoc if ($ARGV[0] eq '--help');
&check_for_needed_programs;


my $date_time = qx|date|; chomp $date_time;

# get seconds today (since mightnight this morning):
# --
my $epoch = qx|date -d '$date_time' +%s|; chomp $epoch;
$date_time =~ /^[\w\s]+(\d\d:\d\d:\d\d)[\w\s]+$/;
my $time_str = $1;
my $date_time_at_midnight = $date_time;
$date_time_at_midnight =~ s/${time_str}/00:00:00/;
my $epoch_at_midnight = qx|date -d '$date_time_at_midnight' +%s|; chomp $epoch_at_midnight;
my $seconds_since_midnight = $epoch - $epoch_at_midnight;
# --


# Add leading zeros to keep seconds field 5 digits long:
# --
my $length = length "$seconds_since_midnight";
my $missing_zeros = 5 - $length;
my $seconds_str;
$seconds_str = "$seconds_since_midnight" if ($missing_zeros == 0);
$seconds_str = '0' . "$seconds_since_midnight" if ($missing_zeros == 1);
$seconds_str = '00' . "$seconds_since_midnight" if ($missing_zeros == 2);
$seconds_str = '000' . "$seconds_since_midnight" if ($missing_zeros == 3);
$seconds_str = '0000' . "$seconds_since_midnight" if ($missing_zeros == 4);
# --

my $timestamp = qx|date -d '$date_time' +%Y-%m-%d|; chomp $timestamp;
$timestamp .= '-s' . $seconds_str;



&printusage if ($ARGV[2]);
&restore_passwords if ($ARGV[0] eq '--restore');
&printusage unless ($ARGV[0] && $ARGV[1]);

my ($usernames, $tmp_pass) = @ARGV;


&set_passwords($usernames,$tmp_pass);





#-----------------------------------------------------------#
#                ---    FUNCTION SECTION    ---             #
#-----------------------------------------------------------#
#

sub display_perldoc {
	system('perldoc', $0);
	exit;
}


sub check_for_needed_programs {
	foreach my $program (@needed_programs) {
		qx|which $program > /dev/null|;
		unless ($? == 0) {
			print "\nRequired program '$program' not found. Can't continue\n";
			exit;
		}
	}
}



sub set_passwords {

	my $usernames = shift;
	my $tmp_pass = shift;
	
	
	if ( -f $current_pw_hashes_db ) {
	
		print "Error.\n\n" .
			"$current_pw_hashes_db exists.\n\n" .
			'It looks like there are already temporarily reset passwords; this' . "\n" .
			'is not supported. Only one set of users can have their passwords' . "\n" .
			'temporarily reset at a time. These will need to be reset by running' . "\n" .
			'"./' . $SCRIPT_NAME . ' --restore" before more users can have their' . "\n" .
			'passwords temporarily reset.' . "\n\n";
		exit;
	}
	
	&read_in_data;
	
	# Single username:
	if ( $usernames =~ /^[^,@]+$/ ) {
		&prepare_set_temp_pass($usernames,$tmp_pass)
	}
	else {
		my @list = split(/\,/, $usernames);
		foreach my $item (@list) {
			# Single username:
			if ( $item =~ /^[^@]+$/ ) {
					&prepare_set_temp_pass($item,$tmp_pass)
			}
			# Group:
			else {
				my @userlist = &get_users_from_group($item);
				foreach my $username (@userlist) {
					&prepare_set_temp_pass($username,$tmp_pass)
				}
			}
		}
	}

	# Remove any duplicate usernames:
	&remove_duplicates_from_array_of_hashes(\@usernames_to_set,'username');

	print "Ready to temporarily set the password of the following usernames to '$tmp_pass':\n\n ";
	foreach my $item (@usernames_to_set) {
		$username_string_list .= "$item->{'username'},";
	}
	$username_string_list =~ s/,$//;
	print "$username_string_list\n\n";
	print "Hit Enter to continue or Ctrl-C to abort: ";
	my $input = <STDIN>;
	
	&build_pw_hashes_db_data;
	&backup_userdb_data;
	&change_passwords;
	
	print "\n" .
		'The passwords have been temporarily set to "' . $tmp_pass . '" but' . "\n" .
		'the original passwords (the encrypted "hashes") have been stored so that' . "\n" .
		'they can be set back to their original values. When you are ready to set' . "\n" .
		'the passwords back to their original values, call this script like this:' . "\n\n " .
		$0 . ' --restore' . "\n\n";
	exit;

}



sub read_in_pw_hashes_db {

	@usernames_to_set = ();
	$username_string_list = '';
	
	unless ( -f $current_pw_hashes_db ) {
		print 	"$current_pw_hashes_db not found.\n" .
					'There doesn\'t appear to be anything to restore.' . "\n";
		exit;
	}

	print "Reading $current_pw_hashes_db ...\n";
	open DB, "< $current_pw_hashes_db"
		or die "Error! Failed to read $current_pw_hashes_db !!!\n";
	
	while (<DB>) {
		# skip comments:
		next if ($_ =~ /^#/);
		chomp $_;
		# Read timestamp line:
		if ($_ =~ /^\(/) {
			my $time_line = $_;
			$time_line =~ s/^\(//;
			$time_line =~ s/\)$//;
			$db_date_time = $time_line;
			next;
		}
		my @arr = split(/\:/,$_);
		my $hashref;
		$hashref->{'username'} = $arr[0];
		$hashref->{'shadow_hash'} = $arr[1];
		$hashref->{'tdb_key'} = $arr[2];
		$hashref->{'tdb_data'} = $arr[3];
		push(@usernames_to_set, $hashref);
		$username_string_list .= "$hashref->{'username'},";
	}
	close DB;
	
	# verify integrity of data:
	foreach my $elem (@usernames_to_set) {
		unless (	$elem->{'username'} && $elem->{'shadow_hash'} &&
						$elem->{'tdb_key'} && $elem->{'tdb_data'}	) {		
			print 
				'Fatal error. The data obtained from the pw_hashes_db appears to be invalid or corrupt.' . "\n";
			exit 1;
		}
	}
	qx|date -d '$db_date_time' >& /dev/null|;
	my $return = $?;
	unless ($return == 0) {
		print "Fatal error. The timestamp in the pw_hashes_db is invalid or corrupt.\n";
		exit 1;
	}
	
	$username_string_list =~ s/,$//;

}




sub backup_userdb_data {

	# Create $pw_hashes_backup_dir if it doesn't exist:
	qx|mkdir -p $pw_hashes_backup_dir| unless (-d $pw_hashes_backup_dir);
	$pw_hashes_backup_dir =~ s/\/$//;
	

	# Write $current_pw_hashes_db:
	print "\nSaving current hash data to $current_pw_hashes_db...\n";
	open FILE, "> $current_pw_hashes_db"
		or die "Couldn't write to $current_pw_hashes_db\nAborting.\n";
	print FILE $current_pw_hashes_db_data;
	close FILE;
	my $hashes_db_backup = $pw_hashes_backup_dir . '/' . $timestamp . '-backup.pw_hashes.db';
	qx|cp -prf $current_pw_hashes_db $hashes_db_backup|;
	
	# Backup shadow:
	my $shadow_file_backup = $pw_hashes_backup_dir . '/' . $timestamp . '-backup.shadow';
	print "Backing up $shadow_file to $shadow_file_backup ...\n";
	qx|cp -prfL $shadow_file $shadow_file_backup|;
	
	# Backup tdb:
	my $tdb_file_backup = $pw_hashes_backup_dir . '/' . $timestamp . '-backup.passdb.tdb';
	print "Backing up $passdb_file to $tdb_file_backup ...\n";
	qx|cp -prfL $passdb_file $tdb_file_backup|;
	
	print "Setting mode 0400 on backup files...\n";
	qx|chmod 0400 $current_pw_hashes_db|;
	qx|chmod 0500 $pw_hashes_backup_dir|;
	qx|chmod 0400 $pw_hashes_backup_dir/*|;

}



sub change_passwords {
	print "\nExecuting commands:\n\n";
	foreach my $item (@usernames_to_set) {
		my $cmd = 'echo "' . $item->{'username'} . ':' . $tmp_pass . '" | chpasswd';
		print " $cmd\n";
		qx|$cmd|;
		$cmd = 'echo -e "' . $tmp_pass . '\n' . $tmp_pass . '\n" |smbpasswd -s ' . $item->{'username'};
		print " $cmd\n";
		qx|$cmd|;
	}
	print "\nFinished.\n";
}




sub build_pw_hashes_db_data {

	$current_pw_hashes_db_data =	
		'#####################################' . "\n" .
		'## User Password Hashes backup file' . "\n" .
		'## Generated by ' . $SCRIPT_NAME . ' ' . $VERSION . ' at ' . $date_time . "\n##\n" .
		'## This file contains a backup of the password hashes from the UNIX (' . $shadow_file .")\n" .
		'## and Samba (' . $passdb_file . ') user databases as they were at ' . $date_time . ".\n##\n" .
		'## This file contains hash backups for the following users:' . "\n##\n##    " . $username_string_list .
		"\n##\n" . 
		'## This file is meant to be used by ' . $SCRIPT_NAME . ' to restore ' . "\n" .
		'## passwords that were temporarily reset for admin purposes.' .
		"\n##\n" . 
		'## The data is stored in colon delimited format, 1 record per line:' . "\n##\n" .
		'## (username:UNIX_shadow_hash:Samba_tdb_key:Samba_tdb_data)' . 
		"\n##\n#####################################\n(" . $date_time . ")\n";

	foreach my $item (@usernames_to_set) {
		$current_pw_hashes_db_data .= 
			$item->{'username'} .':'.
			$item->{'shadow_hash'} .':'.
			$item->{'tdb_key'} .':'.
			$item->{'tdb_data'} . "\n";
	}

}




sub restore_passwords {

	&read_in_pw_hashes_db;
	
	print 
		"About to restore password hashes for the following usernames:\n\n $username_string_list\n\n" .
		"Passwords will be restored to the values they were at '$db_date_time'\n" .
		"Hit Enter to continue, or Ctrl-C to abort: ";
	my $input = <STDIN>;
	
	print "\nExecuting commands:\n\n";
	
	foreach my $item (@usernames_to_set) {
		&reset_unix_password($item);
		&reset_tdb_data($item)
	}
	
	print 
		"\nFinished. Passwords have been set back to their original values." .
		"\n\nRemoving $current_pw_hashes_db\n";
	qx|rm -f $current_pw_hashes_db|;
	
	exit;
}




sub reset_unix_password {
	my $userhash = shift;
	my $cmd = "usermod -p '" . $userhash->{'shadow_hash'} . "' " . $userhash->{'username'};
	print " $cmd\n";
	qx|$cmd|;
}

sub reset_tdb_data {
	my $userhash = shift;
	my $cmd_part1 = 'echo "store ' . $userhash->{'tdb_key'} . ' ';
	my $cmd_part2 = $userhash->{'tdb_data'};
	my $cmd_part3 = '"' .	"| tdbtool $passdb_file";
	my $cmd = $cmd_part1 . $cmd_part2 . $cmd_part3;
	
	my $truncated_cmd_part2 = substr($cmd_part2,0,13);
	$truncated_cmd_part2 .= '...<--snip-->...';
	my $truncated_cmd = $cmd_part1 . $truncated_cmd_part2 . $cmd_part3;
	
	print " $truncated_cmd\n";
	qx|$cmd|;
}



sub get_users_from_group {
	my $group = shift;
	$group =~ s/^\@//;
	foreach my $line (@group_lines) {
		my @arr = split(/\:/,$line);
		return split(/\,/, $arr[3]) if ($arr[0] eq $group);
	}
}


# This function removes all array duplicates (element duplicates) from the array hashes
# (pointers to hashes) where $elem->{$hash_key} is the same:
sub remove_duplicates_from_array_of_hashes {

	my $array_pointer = shift;
	my $hash_key = shift;

	my @unique_array = ();
	my %seen   = ();	
	foreach my $elem ( @{$array_pointer} )
	{
		next if $seen{ $elem->{$hash_key} }++;
		push @unique_array, $elem;
	}	
	@{$array_pointer} = @unique_array;
}



sub prepare_set_temp_pass {

	my $username = shift;
	my $tmp_pass = shift;
	
	
	#Get current data:
	my $old_shadow_entry;
	my $old_tdb_entry;
	foreach my $entry (@shadow_entries) {
		$old_shadow_entry = $entry if ($entry->{'username'} eq $username);
	}
	foreach my $entry (@tdbdump_entries) {
		$old_tdb_entry = $entry if ($entry->{'username'} eq $username);
	}
	unless ($old_shadow_entry->{'hashed_pw'}) {
		print "$username not found in the shadow file.\nAborting.\n";
		exit;
	}
	unless ($old_tdb_entry->{'data'}) {
		print "$username not found in the tdb database.\nAborting.\n";
		exit;
	}
	
	my $hashref;
	
	$hashref->{'username'} = $old_shadow_entry->{'username'};
	$hashref->{'shadow_hash'} = $old_shadow_entry->{'hashed_pw'};
	$hashref->{'tdb_key'} = $old_tdb_entry->{'key'};
	$hashref->{'tdb_data'} = $old_tdb_entry->{'data'};
	
	
	push(@usernames_to_set, $hashref);

}


sub read_in_data {

	@shadow_entries = ();
	my $shadow_contents = qx|cat $shadow_file|;
	my @shadow_lines = split(/\n/,$shadow_contents);
	
	foreach my $line (@shadow_lines) {
		my @entry = split(/\:/,$line);
		my $hashref;
		$hashref->{'username'} = $entry[0];
		$hashref->{'hashed_pw'} = $entry[1];
		push(@shadow_entries, $hashref);
	}
	
	@tdbdump_entries = ();
	my $tdbdump_contents = qx|tdbdump $passdb_file|;
	my @tdb_records = split(/\}/,$tdbdump_contents);
	
	foreach my $record (@tdb_records) {
		$record =~ s/^\n//;
	
		#print "top==============\n$record\nbottom==================\n\n";
	
		my $hashref;
		my @lines = split(/\n/,$record);
		my @key_line = split(/\"/,$lines[1]);
		$hashref->{'key'} = $key_line[1];
		next unless ($hashref->{'key'} =~ /^USER_(\w+)\\00$/);
		#$hashref->{'key'} =~ /^USER_(\w+)\\00$/;
		$hashref->{'username'} = $1;
		my @data_line = split(/\"/,$lines[2]);
		$hashref->{'data'} = $data_line[1];
		
		push(@tdbdump_entries, $hashref);
	}
	
	@group_lines = ();
	my $group_contents = qx|cat $group_file|;
	@group_lines = split(/\n/,$group_contents);
}



#########################
### sub printusage()
##
## usage:
#
# printusage()
#
# Prints the usage statement and exits the program
#
sub printusage {

print "$SCRIPT_NAME\tver: $VERSION

For usage:

  $0 --help

";

exit;

}
