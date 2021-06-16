
// AJAX queueing system, max 3 (default) AJAX requests at once
var EPJS_Stats_running_id = 0;
var EPJS_Stats_max_running = 6;
var EPJS_Stats_running_size = 0;
var EPJS_Stats_running = new Hash();
var EPJS_Stats_queue = new Hash();
var EPJS_Stats_queue_size = 0;

/* Abstract class, not to be used directly */
var EPJS_Stats = Class.create({

	initialize: function(params) {

//		this.queue_lock = false;
//		this.run_lock = true;

		if( params == null )
		{
			alert( 'Missing params in EPJS_Stats' );
			return 0;
		}
	
		var context = params.context;
		var options = params.options;
	
		if( options.container_id == null )
		{
			alert( 'Missing param "container_id" in EPJS_Stats' );
			return 0;
		}
		this.container_id = options.container_id;

		if( options.url != null )
			this.url = options.url;
		else
			this.url = '/cgi/stats/get';

		this.context = new Hash(context);
		this.options = new Hash(options);

		this.ajax_params = new Hash();

		var my_context = this.get_context_fields();

		// sf2 : note that this will set all values even if they are null. This is because of weird inheritances in Prototype classes if you
		// have more than one instance of the same super class on the same page: http://www.prototypejs.org/learn/class-inheritance
		for( var i=0; i < my_context.length; i++ )
			this.ajax_params.set( my_context[i], this.context.get( my_context[i] ) );

		// also add any options to the ajax_params Hash
		this.options.each(function(pair) {
			this.ajax_params.set( pair.key, pair.value );
		}.bind(this));
	},

	get_context_fields: function() {

		return [ 'datatype', 'datafilter', 'grouping', 'set_name', 'set_value', 'range', 'to', 'from' ];
	},

	can_run: function() {
		return EPJS_Stats_running_size < EPJS_Stats_max_running;
	},

	run: function(o) {
		this.running_id = EPJS_Stats_running_id;
		EPJS_Stats_running.set( EPJS_Stats_running_id++, o );
		EPJS_Stats_running_size++;
		o.request();
	},
	
	run_next: function() {

		EPJS_Stats_running.unset( this.running_id );
		if( --EPJS_Stats_running_size < 0 )
			EPJS_Stats_running_size = 0;
		this.running_id = null;
		var o = null
		while( EPJS_Stats_queue_size > 0 && o == null )
		{
			var o = EPJS_Stats_queue.get( EPJS_Stats_queue_size -1 );
			EPJS_Stats_queue.unset( EPJS_Stats_queue_size -1 );
			EPJS_Stats_queue_size--;
		}

		if( o != null )
			this.run(o);	
	},

	queue: function(o) {
		EPJS_Stats_queue.set( EPJS_Stats_queue_size++, this );
	},

	draw: function() {
		this.wait();
		this.ajax_params.set( 'view', this.view );

		if( this.can_run() )
			this.run( this );
		else
			this.queue(this);
	},

	request: function() {
                new Ajax.Request(this.url, {
	                        method: 'get',
				parameters: this.ajax_params,
                	        onSuccess: this.ajax.bind(this),
				onFailure: this.ajax_failure.bind(this)
                });
	},

	ajax_failure: function( response ) {

		if( response != null && response.status == 401 )
		{
			if( this.container_id != null )
			{
				$( this.container_id ).update( '<p class="irstats2_error_login">You must <a href="/cgi/users/login?target='+document.URL+'">login</a> to access Statistics</p>' );
				$( this.container_id ).setStyle( { 'height': 'auto', 'width': 'auto' } );
			}
		}
	},

	ajax: function(response) {

		this.run_next();

	},

	// will show the loading ajax spin	
	wait: function() {
		$( this.container_id ).insert( new Element( 'img', { 'border': '0', 'class': 'irstats2_spin', 'src': '/style/images/loading.gif' } ) );
		$( this.container_id ).insert( '<span class="irstats2_loading">Loading...</span>' );
	}

});

/* Generic View generating HTML */

var EPJS_Stats_View = Class.create(EPJS_Stats, {
	
	initialize: function($super,params) {

        	$super( params );
		this.view = params.options.view;
		this.draw();
	},

	ajax: function($super,response) {

		$super(response);
		var html = response.responseText;
		$( this.container_id ).update( html );
		$( this.container_id ).show();
	}
});


/* Displays a Counter */

var EPJS_Stats_Counter = Class.create(EPJS_Stats, {
	
	initialize: function($super,params) {

        	$super( params );
		this.view = 'Counter';
		this.draw();
	},

	ajax: function($super,response) {

		$super(response);
		var html = response.responseText;
		$( this.container_id ).update( html );
	}


});

/* Displays an HTML Table */

var EPJS_Stats_Table = Class.create(EPJS_Stats, {

	initialize: function($super,params) {

        	$super( params );
		this.view = 'Table';
		this.draw();
	},

        ajax: function($super,response) {

                $super(response);
                var html = response.responseText;
                $( this.container_id ).update( html );

                var pNode = $( this.container_id ).up(2);
                var limit = this.ajax_params.get( 'limit' );
                if( pNode != null && limit != null )
                {
                        var found_limit = false;

                        var inputs = pNode.select( 'input[type="hidden"]' );
                        inputs.each( function(el) {

                                if( el.name == 'limit' && el.value != limit )
                                {
                                        el.value = limit;
                                        found_limit = true;
                                }

                        }.bind(this) );

                        if( !found_limit )
                        {
                                var form = pNode.down('form');
                                if( form != null )
                                        form.insert( new Element( 'input', { 'type': 'hidden', 'name': 'limit', 'value': limit } ) );
                        }

                }
        }

});


var EPJS_Stats_GoogleGraph = Class.create(EPJS_Stats, {

	initialize: function($super,params) {

        	$super( params );
		this.view = 'Google::Graph';
		this.draw();
	},
	
	ajax: function($super,response) {

		$super();

		var json = response.responseText.evalJSON();
		
		var container = $( this.container_id );

		// potential error message (eg. no data points)
		var msg = json.msg
	
		if( msg != null )
		{
			// for summary page
			var elparent = container.up( "div[class=ep_summary_box_body]" );

			if( elparent != null )
			{
				elparent.update( "<p>" + msg + "</p>" );
				return;
			}
		}

		var jsdata = json.data;

		var data = new google.visualization.DataTable();
		data.addColumn('string', 'Year');
		data.addColumn('number', ' ');

		if( json.show_average )
			data.addColumn('number', ' ');

		data.addRows( jsdata );

		var w = container.getWidth() - 20;
		var h = container.getHeight() - 10;

		var type = json.type;
		var chart;

		if( json.show_average )
			chart = new google.visualization.ComboChart( container );
		else
		{
			if( type == null || type == 'area' )
				chart = new google.visualization.AreaChart(container);
			else
				chart = new google.visualization.ColumnChart(container);
		}

		var options = {
			width: w, 
			height: h,
			lineWidth: 3, 
			hAxis: {
				slantedText: false,
				maxAlternation: 1 },
			legend: 'none', 
			vAxis: {
				viewWindowMode: 'explicit', 
				viewWindow: { min: 0 } }
		}

		if( json.show_average )
		{
			options.seriesType = 'bars';	
			options.series = { 1: { type: 'line', lineWidth: 1 } };
		}

		chart.draw( data, options );
	}
});

var EPJS_Stats_GoogleSpark = Class.create(EPJS_Stats, {

	initialize: function($super,params) {

        	$super( params );
		this.view = 'Google::Spark';
		this.draw();
	},
	
	ajax: function($super,response) {

		$super();

		var json = response.responseText.evalJSON();

		var jsdata = json.data;

		var data = new google.visualization.DataTable();
		data.addColumn('string', 'Year');
		data.addColumn('number', ' ');
		data.addRows( jsdata );

		var container = $( this.container_id );
		var w = container.getWidth();
		var h = container.getHeight();

		var chart = new google.visualization.AreaChart(container);

		chart.draw( data, {
				width: w, 
				height: h,
				lineWidth: 1, 
				enableInteractivity: false,
				hAxis: {
					slantedText: false,
					maxAlternation: 1,
					textColor: '#ffffff'
				},
				legend: 'none', 
				vAxis: {
					textColor: '#ffffff',
					viewWindowMode: 'explicit', 
					viewWindow: { min: 0 },
					gridlines: { color: '#ffffff' } 
				}
	 	} );
	}
});

var EPJS_Stats_GoogleGeoChart = Class.create(EPJS_Stats, {

	initialize: function($super,params) {

        	$super( params );
		this.view = 'Google::GeoChart';
		this.draw();
	},
	
	ajax: function($super,response) {

		$super();
		
		var json = response.responseText.evalJSON();
		var jsdata = json.data;

		var data = new google.visualization.DataTable();
		data.addColumn('string', 'Country');
		data.addColumn('number', 'Downloads');
		data.addRows( jsdata );

		var container = $( this.container_id );
		var w = container.getWidth() - 20;
		var h = container.getHeight() - 10;
		
		var options = {'width':w, 'height':h};
		var chart = new google.visualization.GeoChart( container );
		chart.draw(data, options);
	}
});

var EPJS_Stats_GooglePieChart = Class.create(EPJS_Stats, {

	initialize: function($super,params) {

        	$super( params );
		this.view = 'Google::PieChart';
		this.draw();
	},
	
	ajax: function($super,response) {

		$super();
		
		var json = response.responseText.evalJSON();
		var jsdata = json.data;

		var data = new google.visualization.DataTable();
		data.addColumn('string', 'Country');
		data.addColumn('number', 'Downloads');
		data.addRows( jsdata );

		var container = $( this.container_id );
		var w = container.getWidth() - 20;
		var h = container.getHeight() - 10;
		
		var options = {'width':w, 'height':h};
		var chart = new google.visualization.PieChart( container );
		chart.draw(data, options);
	}
});

var EPJS_Stats_Browse = Class.create( {

	initialize: function(params) {

		if( params == null || params.container_id == null )
		{
			alert( 'missing params...' );
			return;
		}
               
		this.container_id = params.container_id;
 
		new Ajax.Updater( this.container_id, '/cgi/stats/browse', {
                        method: 'get',
			parameters: { 'container_id': this.container_id },
			evalScripts: true
                });
	},

	ajax: function(transport) {
		$( this.container_id ).update( transport.responseText );
	}
} );

var EPJS_Set_Finder = function( container_id, select_id, input_id, base_url, context ) {
	
	var select = $( select_id );
	if( select == null )
		return;		

	var selected = select.options[select.selectedIndex];

	// need to escape base_url?
	var target_url = '/cgi/stats/set_finder?set_name=' + selected.value + '&base_url=' + base_url;

	if( context == null )
		context = {};

	if( context.from != null )
		target_url += "&from=" + context.from;
	if( context.to != null )
		target_url += "&to=" + context.to;

	if( input_id != null )
	{
		// used for searching for a value
		var input_el = $( input_id );
		if( input_el != null )
		{
			target_url += "&q=" + input_el.value;
		}
	}

	if( !$( container_id ).visible() )
	{
		$( container_id ).update( new Element( 'img', { 'border':'0', 'src': '/style/images/loading.gif' } ) );	
		$( container_id ).show();
	}
	
	new Ajax.Updater( container_id, target_url, { 'method': 'GET' } );
};

var EPJS_Set_Finder_Autocomplete = function( container_id, select_id, input_id, base_url, context ) {

	var placeholder = 'e.g. Smith, John';

	$( input_id ).observe('keyup', function(event){

		var text = $( input_id ).value;
		if( text != null && text.length > 0 )
			new EPJS_Set_Finder( container_id, select_id, input_id, base_url, context );
	} );

	EPJS_Stats_Placeholder( input_id, placeholder );
};

var EPJS_Stats_Placeholder = function( element_id, message ) {

	$( element_id ).observe( 'click', function(event) {

		if( $( element_id ).value == message )
		{
			$( element_id ).value = '';
			$( element_id ).removeClassName( 'irstats2_placeholder' );
		}

	} );

	$( element_id ).value = message;
	$( element_id ).addClassName( 'irstats2_placeholder' );

};

var EPJS_Stats_Action_Toggled_Element = {};
var EPJS_Stats_Action_Toggle = function( input_el, content_el, extra_css ) {

	var input = $( input_el );
	var content = $( content_el );
	if( input != null && content != null )
	{
		if( !content.visible() )
		{
			if( EPJS_Stats_Action_Toggled_Element.input_el != null )
			{
				// also need to toggle up the potentially other selected element
				var selected_element = EPJS_Stats_Action_Toggled_Element;
				EPJS_Stats_Action_Toggled_Element = {};
				EPJS_Stats_Action_Toggle( selected_element.input_el, selected_element.content_el, selected_element.extra_css );
			}

			Effect.SlideDown( content, { duration: 0.5 } );
			if( extra_css != null )
				input.addClassName( extra_css );
			EPJS_Stats_Action_Toggled_Element = { 'input_el': input_el, 'content_el': content_el, 'extra_css': extra_css };
		}
		else
		{
			content.hide();
			if( extra_css != null )
				input.removeClassName( extra_css );
			EPJS_Stats_Action_Toggled_Element = {};
		}
	}
	return false;
};

var EPJS_Stats_Export_Toggle = function( el, content_id, show_text='Show export options', hide_text='Hide export options' ) {

	var content = $( content_id );
	if( el != null && content != null )
	{
		if( !content.visible() )
		{
			Effect.SlideDown( content, { duration: 0.5 } );
			el.update( hide_text + ' <img border="0" src="/style/images/multi_up.png"/>' );
		}
		else
		{
			content.hide();
			el.update( show_text + ' <img border="0" src="/style/images/multi_down.png"/>' );
		}
	}
	return false;
};
