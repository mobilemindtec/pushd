
function trim(str) {
    str = str.replace(/^\s+/, '');
    for (var i = str.length - 1; i >= 0; i--) {
        if (/\S/.test(str.charAt(i))) {
            str = str.substring(0, i + 1);
            break;
        }
    }
    return str;
}

jQuery.extend( jQuery.fn.dataTableExt.oSort, {
    "num-html-pre": function ( a ) {
        var x = String(a).replace(/(?!^-)[^0-9]/g, "");        
        return parseFloat( x );
    },

    "num-html-asc": function ( a, b ) {        
        return ((a < b) ? -1 : ((a > b) ? 1 : 0));
    },

    "num-html-desc": function ( a, b ) {        
        return ((a < b) ? 1 : ((a > b) ? -1 : 0));
    }
})  
jQuery.extend( jQuery.fn.dataTableExt.oSort, {

    "date-custom-asc": function ( a, b ) {        
        var aDate = new Date()
        var bDate = new Date()

        aDate.setMonth(trim(a).split('/')[0])
        aDate.setFullYear(trim(a).split('/')[1])

        bDate.setMonth(trim(b).split('/')[0])
        bDate.setFullYear(trim(b).split('/')[1])

        return aDate - bDate
    },

    "date-custom-desc": function ( a, b ) {        
        var aDate = new Date()
        var bDate = new Date()

        aDate.setMonth(trim(a).split('/')[0])
        aDate.setFullYear(trim(a).split('/')[1])

        bDate.setMonth(trim(b).split('/')[0])
        bDate.setFullYear(trim(b).split('/')[1])

        return bDate - aDate
 
    }
})  


jQuery.extend( jQuery.fn.dataTableExt.oSort, {

    "date-time-asc": function ( a, b ) {        

        if (trim(a) != '') {
            var frDatea = trim(a).split(' ');
            var frTimea = frDatea[1].split(':');
            var frDatea2 = frDatea[0].split('/');
            var x = (frDatea2[2] + frDatea2[1] + frDatea2[0] + frTimea[0] + frTimea[1]) * 1;
        } else {
            var x = 10000000000000; // = l'an 1000 ...
        }
     
        if (trim(b) != '') {
            var frDateb = trim(b).split(' ');
            var frTimeb = frDateb[1].split(':');
            frDateb = frDateb[0].split('/');
            var y = (frDateb[2] + frDateb[1] + frDateb[0] + frTimeb[0] + frTimeb[1]) * 1;                     
        } else {
            var y = 10000000000000;                    
        }
        var z = ((x < y) ? -1 : ((x > y) ? 1 : 0));
        return z;

    },

    "date-time-desc": function ( a, b ) {        
        
        if (trim(a) != '') {
            var frDatea = trim(a).split(' ');
            var frTimea = frDatea[1].split(':');
            var frDatea2 = frDatea[0].split('/');
            var x = (frDatea2[2] + frDatea2[1] + frDatea2[0] + frTimea[0] + frTimea[1]) * 1;                      
        } else {
            var x = 10000000000000;                    
        }
     
        if (trim(b) != '') {
            var frDateb = trim(b).split(' ');
            var frTimeb = frDateb[1].split(':');
            frDateb = frDateb[0].split('/');
            var y = (frDateb[2] + frDateb[1] + frDateb[0] + frTimeb[0] + frTimeb[1]) * 1;                     
        } else {
            var y = 10000000000000;                    
        }                  
        var z = ((x < y) ? 1 : ((x > y) ? -1 : 0));                  
        return z;   
             
    }
})  