#!/usr/local/bin/perl -w

######## 
#
# This perl script generates an Apple Sales Report (txt) from AppSales .dat files.
#   AppSales did not safed the original reports until rougly mid 2010 (?). 
#   If you did not manually downloaded them, such a converter is handy to import reports into AppSales v2.
#
# Note that this was fastly hacked together (no proper XML Parsing for example) ;-)
#   I assume that it is not bug free: USE AT YOUR OWN RISK !!!
#   I also strongly suggest to backup all data before using this script.
#
# Also, I found no way to get hold of some data (like the Customer Prize). 
#   However, the scipt still seems to provide files that are proper imported in AppSales 
#   (no important infos missing in AppSales, however only checked briefly).
#   IMPORTANT: You need to add your Indentfier, Version and Name in the section below !!!
#
# The probably easiest way to get hold of the dat files is the iPhone Backpup Extractor tool (Copyright Reincubate Ltd.) -> note that I am not affiliated with them in any way.
# You can find a short shell script traversing all .dat files in a directory at the bottom of this file.
#
#
# Copyright Thomas Mangel, Munich, 08/2011.
# 
# Free to distribute, but please do not remove copyright notice.
#
######## 

use Encode qw(encode decode);
use Storable qw(dclone);
use Date::Calc qw(Add_Delta_Days); #use "sudo cpan Date::Calc" to install module if not present


print "\n----- AppSales Plist .dat to sales report txt converter ---\n";
# Input file Determination
my $in_file_str = "demo.dat";
my $argc = @ARGV;
if ($argc == 1){
    $in_file_str = $ARGV[0];
    print "Input file is \"$in_file_str\"\n";
}else{
    print "  no filename given, exiting!\n";
    exit 1;
}

# ------------------ IMPORTANT: Modify this to your apps. -----------------------------
# ---- The data files do not contain this data (Except identifier as fo mid 2010) -----
my %IdentToSKU = (  123456789 => "App1SKU",
                    987654321 => "App2SKU");

my %IdentToVersion = (  123456789 => "1.0.0",
                        987654321 => "1.0.0");

my %NameToIdent = (     "My App Number 1"  => 123456789,
                        "My Second App"       => 987654321  ); 
                        # Name must be the same as in the dat files! See script output for found names!
                       
my $DevName = "Developer Name";
# -------------------------------------------------------------------------------------


my %CountryToCustCurency = ( "DK" => "DKK", "NZ" => "NZD", "HK" => "USD", "CH" => "CHF", "NZ" => "NZD",
"SE" => "SEK", "NO" => "NOK" ); # An ugly hack and incomplete. Customer currency is not available in the dat files, this provides it for countries where it is normally not the same as the currency of proceeds.

# Compute the File-Paths
my $txt_file_str = $in_file_str.".txt";
$txt_file_str =~ s/\.dat//;
my $out_file_str = "out/report_fromconvert_$txt_file_str";
print "Output path is \"$out_file_str\"\n";

# create the outpath, a temporary file and convert it from binary to xml
system ("mkdir out");
system ("cp $in_file_str $txt_file_str");
system ("plutil -convert xml1 $txt_file_str");

# open the Input and Output files
open(READ_FILE,"<:encoding(utf8)","$txt_file_str")
  or die "Error while opening '".$txt_file_str."': $!\n";
open(WRITE_FILE,"> ".$out_file_str)
  or die "Error while opening '".$out_file_str."': $!\n";

# state variables for proper tag identification (ugly, but works)
my $ns_objects_tag_counter = 0;
my $dict_count = 0;
my $class_found = 0;
my $country_string_added = 0;

# line conters to proper identify values after tag (ugly, but works)
my $royalties_lc = 0;
my $transtype_lc = 0;
my $units_lc = 0;
my $string_lc = 0;
my $country_lc = 0;
my $date_line = 0;
my $week_info_line = 0;

# Content Storage
my %coutry_map = ();
my @country_ids = ();
my @country_values = ();
my %AppNames = ();

my @entry_list = ();
my %buy_entry = (); 
my $PurchaseDate = "";
my $isWeek = 0;

# Counters
my $insert_counter = 0;
my $line_count = 0;

while(defined(my $line = <READ_FILE>)) { 
	$line_count += 1;
    
	my $s = $line;
    #print "$s\n";
    
    if ($s =~ /[^<]*<(.*)>[^>]*/){
        my $tag = $1;
        my $close = 0;
        
        if ($s =~ /<\/(.*)>/){
            $close = 1;
            $tag = $1;
        }
        if ($tag eq "dict"){
            if ($close == 0){
                $dict_count += 1;
                
                if ($string_lc > 0 && @string_values > 1 && $string_values[0] ne "NSDate"){
                    #entry ended
                    #print "tag:$tag value:$value\n";
                    $insert_counter ++;
                    
                    $appname = $string_values[0];
                    $buy_entry{"appame"} = $appname;
                    
                    $currency = $string_values[1];
                    $buy_entry{"currency"} = $currency;
                    
                    $ident = 000000000;
                    if (@string_values > 2){
                        $ident = $string_values[2];
                        $buy_entry{"ident"} = $ident;
                    }else{
                        $ident = $NameToIdent{$appname};
                        if (!$ident) {
                        	 $ident = 0;
                        }
                        $buy_entry{"ident"} = $ident;
                    }
                    $AppNames{$appname} = $ident;
                    
                    $version = $IdentToVersion{$ident};
                    if (!$version){
                         $version = "0.0.0";
                        print "  PROBLEM: Could not find version for \"$appname\", set mapping in this perl script!\n";
                    }
                    $buy_entry{"version"} = $version;
                    
                    $SKU = $IdentToSKU{$ident};
                    if (!$SKU){
                        $SKU = "NoSKU";
                        print "  PROBLEM: Could not find SKU for \"$appname\", set mapping in this perl script!\n";
                    }
                    $buy_entry{"sku"} = $SKU;
                    
                    push @entry_list, dclone(\%buy_entry);
                    #print "Found entry number $insert_counter\n";
                    
                    $string_lc = 0;
                    $class_found = 0;
                }
            }else{
                $dict_count -= 1;
            }
        }
        if ($line_count == $week_info_line && $tag eq "true/"){
            #print "set isWeek = 1\n";
            $isWeek = 1;
        }
    }
	
	if ($s =~ /.*<(.*)>(.*)<\/.*>.*/){
		my $tag = $1;
        my $value = $2;
       
        if ($value eq "NS.objects"){
            $ns_objects_tag_counter++;
        }       
        if ($tag eq "key" && $value eq "\$class"){
            $class_found = 1;
            
            %buy_entry = ();
            @string_values = ();
            
            if ($country_string_added == 1){
                # Finding the country information ended -> create a hashmap!!
                for ($i=0;$i<@country_ids;$i++){
                    $coutry_map {$country_ids[$i]} = $country_values[$i];
                }
                $country_string_added = 0;
            }
        }
        
        if ($ns_objects_tag_counter == 1 && $country_string_added == 0 && $tag eq "integer"){
            push(@country_ids,$value);
            $class_found = 0;
        }
       
        if ($ns_objects_tag_counter == 1 && $tag eq "string" && $class_found == 0){
            push(@country_values,$value);
            $country_string_added = 1;
        }
        
        if ($tag eq "string" && $value eq "NSDate"){
            $date_line = $line_count + 2;
        }
        if ($line_count == $date_line && $tag eq "string"){
            $PurchaseDate = $value;
        }
        if ($tag eq "key" && $value eq "isWeek"){
            $week_info_line = $line_count+1;
            #print "found is week\n";
        }
        
        #<key>royalties</key>
        #<real>3.6500000953674316</real>
        #<key>transactionType</key>
        #<integer>1</integer>
        #<key>units</key>
        #<integer>1</integer>
        if ($ns_objects_tag_counter > 1 &&  $class_found == 1){
            if ($tag eq "key" && $value eq "royalties"){
                $royalties_lc++;
            }
            if ($tag eq "key" && $value eq "transactionType"){
                $transtype_lc++;
            }
            if ($tag eq "key" && $value eq "units"){
                $units_lc++;
            }
            if ($tag eq "key" && $value eq "country"){
                $country_lc++;
            }
             
            if ($tag eq "integer" && $country_lc == 1){
                $buy_entry{"country_id"} = $value;
                $country_lc = 0;
            }
            
            if ($tag eq "integer" && $transtype_lc == 1){
                $buy_entry{"transtype"} = $value;
                $transtype_lc = 0;
            }
            if ($tag eq "integer" && $units_lc == 1){
                $buy_entry{"units"} = $value;
                $units_lc = 0;
            }
            if ($tag eq "real" && $royalties_lc == 1){
                $buy_entry{"royalties"} = $value;
                $royalties_lc = 0;
            }
            if ($tag eq "string" && $ns_objects_tag_counter > 1 &&  $class_found == 1){
                $string_lc++;
                #print "tag:$tag value:$value\n";
                push(@string_values,$value);
            }
        }
    }
}


# Compute the proper Start Date in case this is a Weekly Report.
my $FromDate = $PurchaseDate;
if ($isWeek == 1){
    if ($PurchaseDate =~ /(.*)\/(.*)\/(.*)/){
        ($year, $month, $day) = Add_Delta_Days($3,$1,$2,-6);
        $month = $month < 10 ? "0$month" : "$month";
        $day = $day < 10 ? "0$day" : "$day";
        $FromDate = "$month/$day/$year";
        printf "Week: $FromDate -> $PurchaseDate\n";
    }
}else{
    printf "Date: $PurchaseDate\n";
}

# -- Write the output data. --

print WRITE_FILE "Provider\tProvider Country\tSKU\tDeveloper\tTitle\tVersion\tProduct Type Identifier\tUnits\tDeveloper Proceeds\tBegin Date\tEnd Date\tCustomer Currency\tCountry Code\tCurrency of Proceeds\tApple Identifier\tCustomer Price\tPromo Code\tParent Identifier\n";

my %buy_entry_t = ();
my $country;

my $i = 0;
my $num = @entry_list;
for ($i=0;$i<$num;$i++){
    #   print "Country Info $i\n";
    #   print "  sku: $entry_list[$i]{sku}\n";
    #   print "  ident: $entry_list[$i]{ident}\n";
    #   print "  royalty: $entry_list[$i]{royalties}\n";
    #   print "  transtype: $entry_list[$i]{transtype}\n";
    #   print "  units: $entry_list[$i]{units}\n";
    #   print "  app name: $entry_list[$i]{appame}\n";
    #   print "  currency: $entry_list[$i]{currency}\n";
    
        $id_t = $entry_list[$i]{country_id};
        $country = $coutry_map{$id_t};
    #print "  country: id=$id_t => $country\n";
    
        $CustomerCurrency = "";
        $CustomerCurrency = $CountryToCustCurency{$country};
        if (!$CustomerCurrency || $CustomerCurrency eq ""){
            $CustomerCurrency = $entry_list[$i]{currency};
        }
    
        print WRITE_FILE "APPLE".
                "\tUS".
                "\t$entry_list[$i]{sku}".
                "\t$DevName".
                "\t$entry_list[$i]{appame}".
                "\t$entry_list[$i]{version}".
                "\t$entry_list[$i]{transtype}".
                "\t$entry_list[$i]{units}".
                "\t$entry_list[$i]{royalties}".
                "\t$FromDate".
                "\t$PurchaseDate".
                "\t$CustomerCurrency".
                "\t$country".
                "\t$entry_list[$i]{currency}".
                "\t$entry_list[$i]{ident}".
                "\t".
                "\t".
                "\t\n";

}

#print "@country_ids\n";
#print "@country_values\n";
print "Number of Found Entries (Lines): $num\n";
print "Found Appnames and used (or found) Identifiers:\n";

foreach $name ( keys %AppNames ) {
	  print "  Name:\"$name\" - Ident:$AppNames{$name}\n";
	  if ($AppNames{$name} == 0){
	  	  print "     PROBLEM: Could not find identfier in dat, give it in this perl script !!!\n";
	  }
}

close(READ_FILE);
close(WRITE_FILE);

system ("rm $txt_file_str");
printf ("-- end --\n\n");

######################### END ##################################

# A short shell script traversing all dat files:
#
# #!/bin/sh
# for i in `ls *.dat`
# do
#   perl convert_to_sales_txt.pl $i
# done
#