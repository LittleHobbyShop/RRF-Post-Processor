description = "Generic RRF Machine";
vendor = "UnofficialRepRap";
vendorUrl = "https://forum.duet3d.com/topic/14872/fusion-360-fdm-fff-slicing/";
legal = "";
certificationLevel = 2;
minimumRevision = 45633;

longDescription = "Post to export toolpath for generic RepRap Firmware printer in gcode format";

extension = "gcode";
setCodePage("ascii");

capabilities = CAPABILITY_ADDITIVE;
tolerance = spatial(0.002, MM);
highFeedrate = (unit == MM) ? 6000 : 236;

//allow circular planes test
//allowedCircularPlanes = (1 << PLANE_XY);

// needed for range checking, will be effectively passed from Fusion
var printerLimits = {
  x: {min: 0, max: 200.0}, //Defines the x bed size
  y: {min: 0, max: 200.0}, //Defines the y bed size
  z: {min: 0, max: 200.0} //Defines the z bed size
};

var extruderOffsets = [[0, 0, 0], [0, 0, 0]];
var activeExtruder = 0;  //Track the active extruder.

// user-defined properties
properties = {
  printerModel: "Generic RRF Printer",
  postHeatMacro: "",
  onLayerMacro: "",
  onLayerMin: 2,
  heatControl: true,
};

// user-defined property definitions
propertyDefinitions = {
  printerModel: {
    title: "Printer model",
    description: "Select the printer model for generating the gcode.",
    type: "enum",
    values:[
      {title:"Generic RRF Printer", id:"rrf"},
    ]
  },
  postHeatMacro: {
    title: "Post Heat Macro",
    description: "Macro to run after heating. Full M98 path.",
    type: "string",
  },
  onLayerMacro: {
    title: "Layer Change Macro",
    description: "Macro to run at each layer change. Full M98 path.",
    type: "string",
  },
  onLayerMin: {
    title: "Layer Change Min Layer",
    description: "First layer to run Layer Change Macro",
    type: "integer",
  },
  heatControl: {
    title: "Enable heater control",
    description: "Enable heater control",
    type: "boolean"
  }
};

var xyzFormat = createFormat({decimals: (unit == MM ? 3 : 4)});
var xFormat = createFormat({decimals: (unit == MM ? 3 : 4)});
var yFormat = createFormat({decimals: (unit == MM ? 3 : 4)});
var zFormat = createFormat({decimals: (unit == MM ? 3 : 4)});
var gFormat = createFormat({prefix: "G", width: 1, zeropad: false, decimals: 0});
var mFormat = createFormat({prefix: "M", width: 2, zeropad: true, decimals: 0});
var tFormat = createFormat({prefix: "T", width: 1, zeropad: false, decimals: 0});
var pFormat = createFormat({prefix: "P", width: 1, zeropad: false, decimals: 0});
var hFormat = createFormat({prefix: "H", width: 1, zeropad: false, decimals: 0});
var feedFormat = createFormat({decimals: (unit == MM ? 0 : 1)});
var integerFormat = createFormat({decimals:0});
var dimensionFormat = createFormat({decimals: (unit == MM ? 3 : 4), zeropad: false, suffix: (unit == MM ? "mm" : "in")});

var gMotionModal = createModal({force: true}, gFormat); // modal group 1 // G0-G3, ...
var gPlaneModal = createModal({onchange: function () {gMotionModal.reset();}}, gFormat); // modal group 2 // G17-19 //Actually unused
var gAbsIncModal = createModal({}, gFormat); // modal group 3 // G90-91

var xOutput = createVariable({prefix: "X"}, xFormat);
var yOutput = createVariable({prefix: "Y"}, yFormat);
var zOutput = createVariable({prefix: "Z"}, zFormat);
var feedOutput = createVariable({prefix: "F"}, feedFormat);
var eOutput = createVariable({prefix: "E"}, xyzFormat);  // Extrusion length
var sOutput = createVariable({prefix: "S", force: true}, xyzFormat);  // Parameter temperature or speed

//incremental layer count for heater workaround
var incLayerCount = 0

// Writes the specified block.
function writeBlock() {
  writeWords(arguments);
}

function onOpen() {
  getPrinterGeometry();

  if (programName) {
    writeComment(programName);
  }
  if (programComment) {
    writeComment(programComment);
  }

  writeComment("Printer Name: " + machineConfiguration.getVendor() + " " + machineConfiguration.getModel());
  writeComment("Print time: " + xyzFormat.format(printTime) + "s");
  writeComment("Max temp: " + integerFormat.format(getExtruder(1).temperature));
  writeComment("Bed temp: " + integerFormat.format(bedTemp));
  writeComment("Layer Count: " + integerFormat.format(layerCount));
  
  //Extruder 1
  writeComment("Extruder 1 material used: " + dimensionFormat.format(getExtruder(1).extrusionLength));
  writeComment("Extruder 1 material name: " + getExtruder(1).materialName);
  writeComment("Extruder 1 filament diameter: " + dimensionFormat.format(getExtruder(1).filamentDiameter));
  writeComment("Extruder 1 nozzle diameter: " + dimensionFormat.format(getExtruder(1).nozzleDiameter));
  writeComment("Extruder 1 offset x: " + dimensionFormat.format(extruderOffsets[0][0]));
  writeComment("Extruder 1 offset y: " + dimensionFormat.format(extruderOffsets[0][1]));
  writeComment("Extruder 1 offset z: " + dimensionFormat.format(extruderOffsets[0][2]));
  
  //Extruder 2
  if (hasGlobalParameter("ext2-extrusion-len") &&
    hasGlobalParameter("ext2-nozzle-dia") &&
    hasGlobalParameter("ext2-temp") && hasGlobalParameter("ext2-filament-dia") &&
    hasGlobalParameter("ext2-material-name")
  ) {
    writeComment("Extruder 2 material used: " + dimensionFormat.format(getExtruder(2).extrusionLength));
    writeComment("Extruder 2 material name: " + getExtruder(2).materialName);
    writeComment("Extruder 2 filament diameter: " + dimensionFormat.format(getExtruder(2).filamentDiameter));
    writeComment("Extruder 2 nozzle diameter: " + dimensionFormat.format(getExtruder(2).nozzleDiameter));
    writeComment("Extruder 2 max temp: " + integerFormat.format(getExtruder(2).temperature));
    writeComment("Extruder 2 offset x: " + dimensionFormat.format(extruderOffsets[1][0]));
    writeComment("Extruder 2 offset y: " + dimensionFormat.format(extruderOffsets[1][1]));
    writeComment("Extruder 2 offset z: " + dimensionFormat.format(extruderOffsets[1][2]));
  }

  writeComment("width: " + dimensionFormat.format(printerLimits.x.max));
  writeComment("depth: " + dimensionFormat.format(printerLimits.y.max));
  writeComment("height: " + dimensionFormat.format(printerLimits.z.max));
  writeComment("Count of bodies: " + integerFormat.format(partCount));
  writeComment("Version of Fusion: " + getGlobalParameter("version", "0"));
}

function getPrinterGeometry() {
  machineConfiguration = getMachineConfiguration();

  // Get the printer geometry from the machine configuration
  printerLimits.x.min = 0 - machineConfiguration.getCenterPositionX();
  printerLimits.y.min = 0 - machineConfiguration.getCenterPositionY();
  printerLimits.z.min = 0 + machineConfiguration.getCenterPositionZ();

  printerLimits.x.max = machineConfiguration.getWidth() - machineConfiguration.getCenterPositionX();
  printerLimits.y.max = machineConfiguration.getDepth() - machineConfiguration.getCenterPositionY();
  printerLimits.z.max = machineConfiguration.getHeight() + machineConfiguration.getCenterPositionZ();

  //Get the extruder configuration
  extruderOffsets[0][0] = machineConfiguration.getExtruderOffsetX(1);
  extruderOffsets[0][1] = machineConfiguration.getExtruderOffsetY(1);
  extruderOffsets[0][2] = machineConfiguration.getExtruderOffsetZ(1);
  if (numberOfExtruders > 1) {
    extruderOffsets[1] = [];
    extruderOffsets[1][0] = machineConfiguration.getExtruderOffsetX(2);
    extruderOffsets[1][1] = machineConfiguration.getExtruderOffsetY(2);
    extruderOffsets[1][2] = machineConfiguration.getExtruderOffsetZ(2);
  }
}

function onClose() {
  writeBlock(mFormat.format(0), hFormat.format(1));
  writeComment("END OF GCODE");
}

function onComment(message) {
  writeComment(message);
}

function onSection() {
  var range = currentSection.getBoundingBox();
  axes = ["x", "y", "z"];
  formats = [xFormat, yFormat, zFormat];
  for (var element in axes) {
    var min = formats[element].getResultingValue(range.lower[axes[element]]);
    var max = formats[element].getResultingValue(range.upper[axes[element]]);
    if (printerLimits[axes[element]].max < max || printerLimits[axes[element]].min > min) {
      error(localize("A toolpath is outside of the build volume."));
    }
  }
  
  // Reset extrusion distance
  //writeBlock(gFormat.format(92), eOutput.format(0));

  // set unit
  writeBlock(gFormat.format(unit == MM ? 21 : 20));
  writeBlock(gAbsIncModal.format(90)); // absolute spatial co-ordinates
  writeBlock(mFormat.format(82)); // absolute extrusion co-ordinates

  //homing
  //writeRetract(Z); // retract in Z

  //lower build plate before homing in XY
  //var initialPosition = getFramePosition(currentSection.getInitialPosition());
  //writeBlock(gMotionModal.format(1), zOutput.format(initialPosition.z), feedOutput.format(highFeedrate));

  // home XY
  //writeRetract(X, Y);
  //writeBlock(gFormat.format(92), eOutput.format(0));

  if (properties.postHeatMacro !== ""){
    writeComment("Executing post heat macro: " + properties.postHeatMacro);
    writeBlock(mFormat.format(98), "P\"" + properties.postHeatMacro + "\"");
  }

  incLayerCount = 0

}

function onSectionEnd(){
  writeComment("Section End")
}

function onRapid(_x, _y, _z) {
  var x = xOutput.format(_x);
  var y = yOutput.format(_y);
  var z = zOutput.format(_z);
  if (x || y || z) {
    writeBlock(gMotionModal.format(0), x, y, z);
  }
}

function onLinearExtrude(_x, _y, _z, _f, _e) {
  var x = xOutput.format(_x);
  var y = yOutput.format(_y);
  var z = zOutput.format(_z);
  var f = feedOutput.format(_f);
  var e = eOutput.format(_e);
  if (x || y || z || f || e) {
    writeBlock(gMotionModal.format(1), x, y, z, f, e);
  }
}

function onBedTemp(temp, wait) {
  if (incLayerCount > 0 || properties.heatControl){
    if (wait) {
      writeBlock(mFormat.format(190), sOutput.format(temp));
    } else {
      writeBlock(mFormat.format(140), sOutput.format(temp));
    }
  }
}

function onExtruderChange(id) {
  if (id < numberOfExtruders) {
    writeBlock(tFormat.format(id));
    activeExtruder = id;
    xOutput.reset();
    yOutput.reset();
    zOutput.reset();
  } else {
    error(localize("This printer doesn't support the extruder ") + integerFormat.format(id) + " !");
  }
}

function onExtrusionReset(length) {
  eOutput.reset();
  writeBlock(gFormat.format(92), eOutput.format(length));
}

function onLayer(num) {
  writeComment("Layer : " + integerFormat.format(num) + " of " + integerFormat.format(layerCount));
  if (properties.onLayerMacro !== "" && properties.onLayerMin <= num){
    writeComment("Executing layer change macro: " + properties.onLayerMacro);
    writeBlock(mFormat.format(98), "P\"" + properties.onLayerMacro + "\"");
  }
  incLayerCount = num;
}

function onExtruderTemp(temp, wait, id) {
  var extruderString = "";
  extruderString = pFormat.format(id);
  if (incLayerCount > 0 || properties.heatControl){
    if (id < numberOfExtruders) {
      if (wait) {
        writeBlock(gFormat.format(10), pFormat.format(id), sOutput.format(temp));
        writeBlock(mFormat.format(116));
      } else {
        writeBlock(gFormat.format(10), pFormat.format(id), sOutput.format(temp));
      }
    } else {
      error(localize("This printer doesn't support the extruder ") + integerFormat.format(id) + " !");
    }
  }
}

function onFanSpeed(speed, id) {
  // to do handle id information
  if (speed == 0) {
    writeBlock(mFormat.format(106), sOutput.format(0));
  } else {
    writeBlock(mFormat.format(106), sOutput.format(speed));
  }
}

function onParameter(name, value) {
  switch (name) {
  //feedrate is set before rapid moves and extruder change
  case "feedRate":
    if (unit == IN) {
      value /= 25.4;
    }
    setFeedRate(value);
    break;
    //warning or error message on unhandled parameter?
  }
}

//user defined functions
function setFeedRate(value) {
  feedOutput.reset();
  writeBlock(gFormat.format(1), feedOutput.format(value));
}

function writeComment(text) {
  writeln(";" + text);
  var index = text.indexOf("park position");    
    if(index !== -1){
        incLayerCount = 0
    }
}

function writeRetract() {
  if (arguments.length == 0) {
    error(localize("No axis specified for writeRetract()."));
    return;
  }
  var words = []; // store all retracted axes in an array
  for (var i = 0; i < arguments.length; ++i) {
    let instances = 0; // checks for duplicate retract calls
    for (var j = 0; j < arguments.length; ++j) {
      if (arguments[i] == arguments[j]) {
        ++instances;
      }
    }
    if (instances > 1) { // error if there are multiple retract calls for the same axis
      error(localize("Cannot retract the same axis twice in one line"));
      return;
    }
    switch (arguments[i]) {
    case X:
      words.push("X" + xyzFormat.format(machineConfiguration.hasHomePositionX() ? machineConfiguration.getHomePositionX() : 0));
      xOutput.reset();
      break;
    case Y:
      words.push("Y" + xyzFormat.format(machineConfiguration.hasHomePositionY() ? machineConfiguration.getHomePositionY() : 0));
      yOutput.reset();
      break;
    case Z:
      words.push("Z" + xyzFormat.format(0));
      zOutput.reset();
      retracted = true; // specifies that the tool has been retracted to the safe plane
      break;
    default:
      error(localize("Bad axis specified for writeRetract()."));
      return;
    }
  }
  if (words.length > 0) {
    gMotionModal.reset();
    writeBlock(gFormat.format(28), gAbsIncModal.format(90), words); // retract
  }
}