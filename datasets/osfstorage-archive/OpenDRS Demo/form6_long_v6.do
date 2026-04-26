* Mazira data processing - form6 long
* Charles Arnold

* This dofile will create the long version of form 6


	local doversion = "v6"

* load data
	clear
	set more off
	use `"$dataoutput_dir$downloaddate\mazira_form6_24hrrecall_$downloaddate.dta"', clear

		
* add dofile indicator
	gen drlong= `"`doversion'"'		


* change childid if home revisit so unique
	sort childid drvisitcode drdate
	gen longchildid = childid
	
	by childid drvisitcode: replace longchildid = childid*100 + 41 if drvisitcode == 4 & _n == 1
	by childid drvisitcode: replace longchildid = childid*100 + 42 if drvisitcode == 4 & _n == 2
	by childid drvisitcode: replace longchildid = childid*100 + 43 if drvisitcode == 4 & _n == 3
	by childid drvisitcode: replace longchildid = childid*100 + 44 if drvisitcode == 4 & _n == 4
	by childid drvisitcode: replace longchildid = childid*100 + 45 if drvisitcode == 4 & _n == 5
	by childid drvisitcode: replace longchildid = childid*100 + 46 if drvisitcode == 4 & _n == 6
	by childid drvisitcode: replace longchildid = childid*100 + 47 if drvisitcode == 4 & _n == 7
	by childid drvisitcode: replace longchildid = childid*100 + 48 if drvisitcode == 4 & _n == 8
	
	by childid drvisitcode: replace longchildid = childid*100 + 31 if drvisitcode == 3 & _n == 1
	
	by childid drvisitcode: replace longchildid = childid*100 + 61 if drvisitcode == 6 & _n == 1


* make long pass 1 2 3

	preserve
	
		* exist if no foods reported
		replace foodnumber_1 = "0" if missing(foodnumber_1)	
	
		* drop pass 4 vars
		drop pass4_count - correctionb_3
		
		* drop scto vars
		drop ingselect*
		
		* save variable labels
		local stemlist "foodnumber_	drfooddesc_	fooddesc4pass2_	pass2index_	drtimecons_	timeconslabel_	filterone_	filtertwoselect_	filtertwo_	drfoodlistcode_	drfoodlistdesc_	drfoodlistos_	reclist_ saucemark_ drfishsauce_ drfishsos_ drmeatsauce_ drmeatsos_	dringredientos_	dringredient1_	dringredient2_	dringredient3_	dringredient4_	dringredient5_	dringredient6_	dringredient7_	dringredient8_	dringredient9_	dringredient10_	dringredient11_	dringredient12_	dringredient13_	dringredient14_	dringredient15_	ingdesc1_	ingdesc2_	ingdesc3_	ingdesc4_	ingdesc5_	ingdesc6_	ingdesc7_	ingdesc8_	ingdesc9_	ingdesc10_	ingdesc11_	ingdesc12_	ingdesc13_	ingdesc14_	ingdesc15_	listingred_	fooddesc4pass3_	spec4pass3_	time4pass3_	pass3index_	drportionmthd_	drportionutensil_	drportionuos_	utdesc_	mthddesc_	drportion_"
		foreach s of local stemlist {
			local `s'lab : var label `s'1
			display `"``s'lab'"'
		}
		
		* reshape
		reshape long foodnumber_	drfooddesc_	fooddesc4pass2_	pass2index_	drtimecons_	timeconslabel_	filterone_	filtertwoselect_	filtertwo_	drfoodlistcode_	drfoodlistdesc_	drfoodlistos_	reclist_ saucemark_ drfishsauce_ drfishsos_ drmeatsauce_ drmeatsos_	dringredientos_	dringredient1_	dringredient2_	dringredient3_	dringredient4_	dringredient5_	dringredient6_	dringredient7_	dringredient8_	dringredient9_	dringredient10_	dringredient11_	dringredient12_	dringredient13_	dringredient14_	dringredient15_	ingdesc1_	ingdesc2_	ingdesc3_	ingdesc4_	ingdesc5_	ingdesc6_	ingdesc7_	ingdesc8_	ingdesc9_	ingdesc10_	ingdesc11_	ingdesc12_	ingdesc13_	ingdesc14_	ingdesc15_	listingred_	fooddesc4pass3_	spec4pass3_	time4pass3_	pass3index_	drportionmthd_	drportionutensil_	drportionuos_	utdesc_	mthddesc_	drportion_ ///
				, i(longchildid) j(repeatno)
		
		* restore labels
		foreach s of local stemlist {
			label variable `s' `"``s'lab'"'
		}		

		* rename and format
		rename foodcount_p1 pass1_count
		order drvisitcode foodnumber, after(childid)
		
		rename *_ *
		
		gen fooddesc_pass1 = drfooddesc
		rename fooddesc4pass2 fooddesc_pass2
		rename fooddesc4pass3 fooddesc_pass3

		gen pass1index = foodnumber	
		replace pass1index = "" if pass1index == "0"
		destring foodnumber repeatno *index, replace
		replace foodnumber = repeatno if foodnumber != repeatno & foodnumber != 0 & ///
				(!missing(pass2index) | !missing(pass3index))
		drop repeatno
		order pass1index pass1_count fooddesc_pass1 pass2index pass2_count fooddesc_pass2 pass3index pass3_count fooddesc_pass3 spec4pass3 time4pass3, last		
		order childid foodnumber drvisitcode
		
		* drop duplicate rows
		drop if missing(foodnumber)
			
		* check descriptions match
		list childid foodnumber *index fooddesc* if foodnumber != pass1index | foodnumber != pass2index | pass1index != pass3index | pass1index != pass3index
		
		* save
		tempfile temp123
		save `temp123'
		
	restore
		

*/		
		
* add back 'additional foods pass'

		* keep vars
		keep longchildid childid drvisitcode drmissingfoods - correctionb_3 drversion drduration drdate drintid drlanguage drchildid1 drchildid2 drstillbf dragelastbf drnumbfs ///
			foodcount_add foodcount_raw drill24 drunusual drunusualsp drunusualos drfeast drfast drmarket drvitamin drvittype drvitdesc drvitsource drdataissue drfreecomm drspeedcount drspeedlist formdef_version submissiondate starttime endtime drdownload drclean drlong

		* drop scto vars
		drop ingselect*
		
		* match to old versions
		rename *b_* *_*		
		rename addfoodnumber_* foodnumber_*
			
		* save variable labels
		local stemlist "foodnumber_	drfooddesc_ 	drtimecons_	timeconslabel_	filterone_	filtertwoselect_	filtertwo_	drfoodlistcode_	drfoodlistdesc_	drfoodlistos_	reclist_   dringredientos_	dringredient1_	dringredient2_	dringredient3_	dringredient4_	dringredient5_	dringredient6_	dringredient7_	dringredient8_	dringredient9_	dringredient10_	dringredient11_	dringredient12_	dringredient13_	dringredient14_	dringredient15_	ingdesc1_	ingdesc2_	ingdesc3_	ingdesc4_	ingdesc5_	ingdesc6_	ingdesc7_	ingdesc8_	ingdesc9_	ingdesc10_	ingdesc11_	ingdesc12_	ingdesc13_	ingdesc14_	ingdesc15_	listingred_		drportionmthd_	drportionutensil_	drportionuos_	utdesc_	mthddesc_	drportion_"
		foreach s of local stemlist {
			local `s'lab : var label `s'1
			display `"``s'lab'"'
		}
		
		* reshape
		reshape long foodnumber_	drfooddesc_ 	drtimecons_	timeconslabel_	filterone_	filtertwoselect_	filtertwo_	drfoodlistcode_	drfoodlistdesc_	drfoodlistos_	reclist_   dringredientos_	dringredient1_	dringredient2_	dringredient3_	dringredient4_	dringredient5_	dringredient6_	dringredient7_	dringredient8_	dringredient9_	dringredient10_	dringredient11_	dringredient12_	dringredient13_	dringredient14_	dringredient15_	ingdesc1_	ingdesc2_	ingdesc3_	ingdesc4_	ingdesc5_	ingdesc6_	ingdesc7_	ingdesc8_	ingdesc9_	ingdesc10_	ingdesc11_	ingdesc12_	ingdesc13_	ingdesc14_	ingdesc15_	listingred_		drportionmthd_	drportionutensil_	drportionuos_	utdesc_	mthddesc_	drportion_ ///
			, i(longchildid) j(repeatno)
		
		* restore labels
		foreach s of local stemlist {
			label variable `s' `"``s'lab'"'
		}		

		* rename and format
		order drvisitcode foodnumber, after(childid)	
		
		rename *_ *
		
		gen fooddesc_pass1 = drfooddesc

		gen pass1index = foodnumber	
		replace pass1index = "" if pass1index == "0"
		destring foodnumber repeatno *index, replace
		replace foodnumber = repeatno if foodnumber != repeatno & foodnumber != 0 
		drop repeatno
		order childid foodnumber drvisitcode
		
		* drop duplicate rows
		drop if missing(foodnumber) | (missing(drtimecons) & missing(drportion))
			
		* drop 
		drop revcorrect* correction* drmissingfoods
		
		* make sure foodnumber doesn't overlap
		replace foodnumber = foodnumber + 100
		
		* save
		tempfile tempadd
		save `tempadd'
		
	
* append
	use `temp123', clear
	append using `tempadd', gen(forgottenfood)
	order forgottenfood, after(foodnumber)
	
	sort longchildid drdate
	
	order childid drvisitcode longchildid foodnumber forgottenfood 
	label variable foodnumber "Numbers less than 100 in first section, larger than 100 are forgotten foods"
	label variable forgottenfood "Foods that were forgotten and added in last section"
	label variable longchildid "Identifies childid plus visit code occurrence"
	saveold `"$dataoutput_dir$downloaddate\mazira_form6long_24hrr_$downloaddate.dta"', replace version(13)

