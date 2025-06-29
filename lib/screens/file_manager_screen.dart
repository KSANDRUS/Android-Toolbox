import 'dart:io';
import 'package:adb_gui/components/file_transfer_progress.dart';
import 'package:adb_gui/components/icon_name_material_button.dart';
import 'package:adb_gui/components/material_ribbon.dart';
import 'package:adb_gui/components/obtainRootDialog.dart';
import 'package:adb_gui/components/simple_file_transfer_progress.dart';
import 'package:adb_gui/models/file_transfer_job.dart';
import 'package:adb_gui/models/item.dart';
import 'package:adb_gui/models/storage.dart';
import 'package:adb_gui/services/adb_services.dart';
import 'package:adb_gui/services/android_api_checks.dart';
import 'package:adb_gui/services/file_services.dart';
import 'package:adb_gui/utils/enums.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:adb_gui/models/device.dart';
import 'package:shimmer/shimmer.dart';
import 'package:system_theme/system_theme.dart';
import '../components/custom_list_tile.dart';
import '../utils/vars.dart';

class FileManagerScreen extends StatefulWidget {
  final Device device;
  const FileManagerScreen({Key? key, required this.device}) : super(key: key);

  @override
  _FileManagerScreenState createState() => _FileManagerScreenState(device);
}

class _FileManagerScreenState extends State<FileManagerScreen> with SingleTickerProviderStateMixin {

  final Device device;

  final List<FileTransferJob> _fileTransferJobs = [];
  int _totalJobCount = 0;

  _FileManagerScreenState(this.device);

  late String _currentPath;
  late final TextEditingController _addressBarEditingController;
  late final TextEditingController _renameFieldController;
  final ScrollController _filesGridScrollController=ScrollController();
  late StateSetter _ribbonStateSetter;

  final _addressBarFocus = FocusNode();
  final _renameItemFocus = FocusNode();

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  late List<Storage> storages;

  late Storage selectedStorage;
  bool _storagesLoaded=false;

  late ADBService adbService;


  Future<void> fetchExternalStorages() async{
    storages=[];
    storages.add(Storage("/sdcard/", "0"));
    storages.addAll(await adbService.getExternalStorages());
    setState(() {
      selectedStorage=storages.first;
      _currentPath=storages.first.path;
      _addressBarEditingController.text=_currentPath;
      _storagesLoaded=true;
    });
  }






  void addFileTransferJob(FileTransferType fileTransferType, String itemName) {
    FileTransferJob newJob =
        FileTransferJob(fileTransferType, _currentPath + itemName, itemName);

    for (int i = 0; i < _fileTransferJobs.length; i++) {
      if (_fileTransferJobs[i].checkSameItem(newJob)) {
        if (_fileTransferJobs[i].jobType == newJob.jobType) {
          return;
        }
        _ribbonStateSetter(() {
          _fileTransferJobs[i] = newJob;
        });
        return;
      }
    }
    _ribbonStateSetter(() {
      if (_fileTransferJobs.length < 4) {
        _fileTransferJobs.add(newJob);
      } else {
        _fileTransferJobs[(_totalJobCount) % 4] = newJob;
      }
      _totalJobCount++;
    });
  }

  void addPath(String fileItemName) async {
    // if (await findFileItemType(adbService,_currentPath,fileItemName) == FileContentTypes.file) {
    //   return;
    // }
    setState(() {
      _renameFieldController.text="";
      if (_currentPath[_currentPath.length - 1] != "/") {
        _currentPath += "/";
      }
      _currentPath += "$fileItemName/";
      _addressBarEditingController.text = _currentPath;
      _addressBarFocus.requestFocus();
      _addressBarEditingController.selection=TextSelection.fromPosition(TextPosition(offset: _addressBarEditingController.text.length));
      Future.delayed(const Duration(microseconds: 1),(){
        _addressBarFocus.unfocus();
      });
    });
  }

  void removePath() {
    List<String> directories = _currentPath.split("/");
    if (_currentPath == "/") {
      return;
    }
    String newPath = "";
    int toRemove = _currentPath[_currentPath.length - 1] == "/" ? 2 : 1;
    for (int i = 0; i < directories.length - toRemove; i++) {
      newPath += "${directories[i]}/";
    }
    setState(() {
      _currentPath = newPath;
      _addressBarEditingController.text = _currentPath;
    });
  }

  void transferFile(FileTransferType fileTransferType, int index,
      BuildContext context) async {
    Process process;

    if (fileTransferType == FileTransferType.move) {
      process=await adbService.fileMove(oldPath: _fileTransferJobs[index].itemPath, newPath: _currentPath);
    } else {
      process=await adbService.fileCopy(oldPath: _fileTransferJobs[index].itemPath, newPath: _currentPath);
    }

    await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => SimpleFileTransferProgress(
          process: process,
          fileTransferType: fileTransferType,
        ));
    setState(() {
      _fileTransferJobs.removeAt(index);
    });
  }

  void renameItem(String itemName,String newName) async {
    if(itemName==newName){
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("New name cannot be the same as old name")));
      ScaffoldMessenger.of(context).deactivate();
      return;
    }else if(newName.endsWith(" ") || newName.endsWith("\r") || newName.endsWith(" \r") || newName.endsWith("\r ")){
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Invalid Name")));
      Scaffold.of(context).deactivate();
    }

    ProcessResult result = await adbService.fileRename(oldPath: _currentPath + itemName, newPath: _currentPath + newName);

    if (result.exitCode == 0) {
      setState(() {
        _renameFieldController.text="";
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("Renamed $itemName to $newName")));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Failed to rename! Check if new name is valid! It must not contain spaces or special characters")));
    }
  }

  void updatePathFromTextField(String value) {
    setState(() {
      if (value.isEmpty) {
        _currentPath = "/";
        _addressBarEditingController.text = "/";
        return;
      }
      _currentPath = value[value.length - 1] == "/" ? value : "$value/";
      _addressBarEditingController.text = _currentPath;
    });
    _addressBarFocus.previousFocus();
  }

  void onObtainingRoot(){
    setState((){});
  }



  @override
  void initState() {
    adbService=ADBService(device: device);
    fetchExternalStorages();
    _addressBarEditingController = TextEditingController();
    _renameFieldController = TextEditingController();

    _animationController=AnimationController(vsync: this,duration: const Duration(milliseconds: 500));
    _fadeAnimation=Tween<double>(
      begin: 0,
      end: 1,
    ).animate(CurvedAnimation(parent: _animationController, curve: Curves.decelerate));

    super.initState();
  }

  @override
  void dispose() {
    _renameFieldController.dispose();
    _addressBarEditingController.dispose();
    _addressBarFocus.dispose();
    _renameItemFocus.dispose();
    _animationController.dispose();
    _filesGridScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        LayoutBuilder(
            builder: (context, constraints) => Column(
                  children: [
                    MaterialRibbon(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.arrow_back_rounded),
                            color: SystemTheme.accentColor.accent,
                            splashRadius: 1,
                            onPressed: () {
                              removePath();
                            },
                          ),
                          Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                                child: TextField(
                                  controller: _addressBarEditingController,
                                  focusNode: _addressBarFocus,
                                  textAlign: TextAlign.left,
                                  textAlignVertical: TextAlignVertical.top,
                                  maxLengthEnforcement: MaxLengthEnforcement.none,
                                  maxLines: 1,
                                  onSubmitted: updatePathFromTextField,
                                  decoration: InputDecoration(
                                    contentPadding: const EdgeInsets.all(8),
                                    border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(18)
                                    ),
                                    focusColor: SystemTheme.accentColor.accent,
                                    suffixIcon: _addressBarFocus.hasFocus
                                        ? IconButton(
                                      icon: const Icon(
                                          Icons.arrow_forward_rounded),
                                      hoverColor: Colors.transparent,
                                      splashRadius: 1,
                                      splashColor: Colors.transparent,
                                      onPressed: () {
                                        updatePathFromTextField(
                                            _addressBarEditingController
                                                .text);
                                      },
                                    )
                                        : IconButton(
                                      icon: const Icon(Icons.refresh),
                                      hoverColor: Colors.transparent,
                                      splashColor: Colors.transparent,
                                      splashRadius: 1,
                                      onPressed: () {
                                        setState(() {});
                                      },
                                    ),
                                  ),
                                ),
                              )),
                          if(_storagesLoaded)
                            DropdownButton(
                              borderRadius: BorderRadius.circular(18),
                              underline: Container(),
                              value: selectedStorage,
                              dropdownColor: Theme.of(context).brightness==Brightness.light?Colors.white:null,
                              items: [
                                for(int i=0;i<storages.length;i++)
                                  DropdownMenuItem(
                                    value: storages[i],
                                    child: CustomListTile(
                                        icon: Icon(storages[i].name=="0"?Icons.storage_rounded:Icons.sd_card_rounded,color: SystemTheme.accentColor.accent,),
                                        title: storages[i].name=="0"?"Internal Storage":storages[i].name
                                    ),
                                  ),
                              ],
                              onChanged: (value){
                                if(!newStoragePathSupported(device.androidAPILevel)){
                                  return;
                                }
                                if(value!=selectedStorage){
                                  setState(() {
                                    selectedStorage=value as Storage;
                                    _currentPath=selectedStorage.path;
                                    _addressBarEditingController.text=_currentPath;
                                  });
                                }
                              }
                            ),
                          Padding(
                            padding: const EdgeInsets.only(left:8.0),
                            child: PopupMenuButton(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(18),
                                ),
                                padding: const EdgeInsets.all(8.0),
                                child: Row(
                                  children: [
                                    Icon(
                                      FontAwesomeIcons.upload,
                                      color: SystemTheme.accentColor.accent,
                                    ),
                                    SizedBox.fromSize(
                                      size: const Size(4, 0),
                                    ),
                                    Text(
                                      "Upload Items",
                                      style: TextStyle(
                                        fontSize: 15,
                                        color: SystemTheme.accentColor.accent,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              itemBuilder: (context) => [
                                PopupMenuItem(
                                  child: Row(
                                    mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                    children: [
                                      Icon(
                                        FontAwesomeIcons.fileUpload,
                                        color: SystemTheme.accentColor.accent,
                                      ),
                                      Text(
                                        "Upload File",
                                        style: TextStyle(color: SystemTheme.accentColor.accent),
                                      ),
                                    ],
                                  ),
                                  onTap: () {
                                    adbService.uploadContent(
                                        currentPath: _currentPath,
                                        uploadType:FileItemType.file,
                                        onProgress: (process,getSourceSize,getDestinationSize,sourcePath,destinationPath) async{
                                          await showDialog(
                                              context: context,
                                              barrierDismissible: false,
                                              builder: (context) => FileTransferProgress(process: process,fileTransferType: FileTransferType.pcToPhone,getSourceSize: getSourceSize,getDestinationSize: getDestinationSize,sourcePath: sourcePath,destinationPath: destinationPath,));
                                          setState(() {});
                                        }
                                    );
                                  },
                                ),
                                PopupMenuItem(
                                  child: Row(
                                    mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                    children: [
                                      Icon(
                                        FontAwesomeIcons.folderPlus,
                                        color: SystemTheme.accentColor.accent,
                                      ),
                                      Text(
                                        "Upload Folder",
                                        style: TextStyle(color: SystemTheme.accentColor.accent),
                                      )
                                    ],
                                  ),
                                  onTap: () {
                                    adbService.uploadContent(
                                        currentPath: _currentPath,
                                        uploadType:FileItemType.directory,
                                        onProgress: (process,getSourceSize,getDestinationSize,sourcePath,destinationPath) async{
                                          await showDialog(
                                              context: context,
                                              barrierDismissible: false,
                                              builder: (context) => FileTransferProgress(process: process,fileTransferType: FileTransferType.pcToPhone,getSourceSize: getSourceSize,getDestinationSize: getDestinationSize,sourcePath: sourcePath,destinationPath: destinationPath,));
                                          setState(() {});
                                        }
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                          PopupMenuButton(
                            icon: Icon(
                              Icons.more_vert_rounded,
                              color: SystemTheme.accentColor.accent,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                            itemBuilder: (context)=>[
                              PopupMenuItem(
                                child: FutureBuilder(
                                  future: adbService.amIRoot(),
                                  builder: (BuildContext context, AsyncSnapshot<bool> snapshot){
                                    return ListTile(
                                      leading: Icon(
                                        FontAwesomeIcons.hashtag,
                                        color: Theme.of(context).brightness==Brightness.light?SystemTheme.accentColor.accent:null,
                                      ),
                                      dense:false,
                                      enabled: snapshot.connectionState==ConnectionState.waiting?false:!snapshot.data!,
                                      title: snapshot.connectionState==ConnectionState.waiting?const LinearProgressIndicator():Text(
                                        "Root Mode",
                                        style: TextStyle(
                                          color: Theme.of(context).brightness==Brightness.light?SystemTheme.accentColor.accent:null,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                                onTap: (){
                                  Future.delayed(const Duration(seconds: 0),() async {
                                    await showDialog(
                                      context: context,
                                      barrierDismissible: false,
                                      builder: (context)=>ObtainRootDialog(obtainRoot: adbService.obtainRoot, onCompleted: onObtainingRoot),
                                    );
                                  });
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    AnimatedSize(
                      duration: const Duration(milliseconds: 250),
                      child: StatefulBuilder(
                        builder: (BuildContext context, StateSetter setState){
                          _ribbonStateSetter=setState;
                          if (_fileTransferJobs.isNotEmpty){
                            return MaterialRibbon(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 10),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.max,
                                  children: [
                                    for (int i = 0; i < _fileTransferJobs.length; i++)
                                      ClipboardChip(
                                        itemName: _fileTransferJobs[i].itemName,
                                        jobIndex: i,
                                        fileTransferType: _fileTransferJobs[i].jobType,
                                        transferFile: transferFile,
                                        parentContext: context,
                                      ),
                                    const Spacer(),
                                    IconNameMaterialButton(
                                        icon: const Icon(
                                          Icons.clear_all_rounded,
                                          size: 35,
                                          color: Colors.blueGrey,
                                        ),
                                        text: const Text(
                                          "Clear",
                                          style: TextStyle(
                                              color: Colors.blueGrey, fontSize: 20),
                                        ),
                                        onPressed: () {
                                          _ribbonStateSetter(() {
                                            _totalJobCount = 0;
                                            _fileTransferJobs.clear();
                                          });
                                        }),
                                  ],
                                ),
                              ),
                            );
                          }
                          return Container();
                        },
                      ),
                    ),
                  ],
                )),
        if(_storagesLoaded)
          Expanded(
            child: FutureBuilder(
              future: adbService.getDirectoryContents(_currentPath),
              builder: (BuildContext context, AsyncSnapshot<List<Item>> snapshot) {

                _animationController.forward(from: 0);

                if (snapshot.connectionState!=ConnectionState.done || !snapshot.hasData) {
                  return FadeTransition(
                    opacity: _fadeAnimation,
                    child: Shimmer.fromColors(
                      baseColor: Theme.of(context).brightness==Brightness.light?const Color(0xFFE0E0E0):Colors.black12,
                      highlightColor: Theme.of(context).brightness==Brightness.light?const Color(0xFFF5F5F5):Colors.blueGrey,
                      enabled: true,
                      child: GridView.builder(
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3, mainAxisExtent: 75
                          ),
                          controller: _filesGridScrollController,
                          cacheExtent: 20,
                          itemCount: int.parse((MediaQuery.of(context).size.height/25).toStringAsFixed(0)),
                          itemBuilder: (context,index){
                            return Row(
                              children: [
                                SizedBox.fromSize(
                                  size: const Size(25, 0),
                                ),
                                Container(
                                  height:20,
                                  width:20,
                                  decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.black,
                                  ),
                                ),
                                SizedBox.fromSize(
                                  size: const Size(25, 0),
                                ),
                                Expanded(
                                  child: Container(
                                    width: double.infinity,
                                    height: 25,
                                    decoration: BoxDecoration(
                                      color: Colors.black,
                                      borderRadius: BorderRadius.circular(25)
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                      ),
                    ),
                  );
                }

                if (snapshot.data!.isEmpty) {
                  return FadeTransition(
                    opacity: _fadeAnimation,
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(
                            FontAwesomeIcons.solidFolderOpen,
                            color: Colors.grey,
                            size: 100,
                          ),
                          Text(
                            "Directory is Empty",
                            style: TextStyle(color: Colors.grey, fontSize: 30),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                return FadeTransition(
                  opacity: _fadeAnimation,
                  child: GridView.builder(
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3, mainAxisExtent: 75),
                      itemCount: snapshot.data!.length,
                      itemBuilder: (context, index) {

                        return StatefulBuilder(
                          builder: (BuildContext context, StateSetter setState){
                            if(_renameFieldController.text!=snapshot.data![index].itemName){
                              return MaterialButton(
                                onPressed: () async {
                                  if(await snapshot.data![index].itemContentType==FileContentTypes.directory){
                                    setState(() {
                                      addPath(snapshot.data![index].itemName);
                                    });
                                  }else{
                                    adbService.downloadContent(
                                        itemPath:_currentPath+snapshot.data![index].itemName,
                                        onProgress: (process,getSourceSize,getDestinationSize,sourcePath,destinationPath) async{
                                          await showDialog(
                                              context: context,
                                              barrierDismissible: false,
                                              builder: (context) => FileTransferProgress(process: process,fileTransferType: FileTransferType.phoneToPC,getSourceSize: getSourceSize,getDestinationSize: getDestinationSize,sourcePath: sourcePath,destinationPath: destinationPath,));
                                          setState(() {});
                                        }
                                    );
                                  }
                                },
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(18)
                                ),
                                elevation: 5,
                                hoverElevation: 10,
                                child: Row(
                                  children: [
                                    SizedBox.fromSize(
                                      size: const Size(25, 0),
                                    ),
                                    FutureIcon(iconData: getFileIconByType(snapshot.data![index].itemContentType)),
                                    SizedBox.fromSize(
                                      size: const Size(25, 0),
                                    ),
                                    Expanded(
                                      child: Text(
                                        snapshot.data![index].itemName,
                                        maxLines: 3,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 15),
                                      ),
                                    ),
                                    FutureBuilder(
                                      future: snapshot.data![index].itemContentType,
                                      builder: (BuildContext context, AsyncSnapshot<FileContentTypes> fileContentTypeSnapshot){
                                        if(!snapshot.hasData){
                                          return const CircularProgressIndicator();
                                        }

                                        return PopupMenuButton(
                                          icon: const Icon(
                                            Icons.more_vert_rounded,
                                            color: Colors.blueGrey,
                                          ),
                                          shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(18)
                                          ),
                                          itemBuilder: (context) => [
                                            PopupMenuItem(
                                              child: ListTile(
                                                  leading: Icon(
                                                    FontAwesomeIcons.download,
                                                    color: Theme.of(context).brightness==Brightness.light?SystemTheme.accentColor.accent:null,
                                                  ),
                                                  dense:false,
                                                  title: Text(
                                                    "Download",
                                                    style: TextStyle(
                                                      color: Theme.of(context).brightness==Brightness.light?SystemTheme.accentColor.accent:null,
                                                    ),
                                                  )),
                                              onTap: () {
                                                adbService.downloadContent(
                                                    itemPath:_currentPath+snapshot.data![index].itemName,
                                                    onProgress: (process,getSourceSize,getDestinationSize,sourcePath,destinationPath) async{
                                                      await showDialog(
                                                          context: context,
                                                          barrierDismissible: false,
                                                          builder: (context) => FileTransferProgress(process: process,fileTransferType: FileTransferType.phoneToPC,getSourceSize: getSourceSize,getDestinationSize: getDestinationSize,sourcePath: sourcePath,destinationPath: destinationPath,));
                                                      setState(() {});
                                                    }
                                                );
                                              },
                                            ),
                                            PopupMenuItem(
                                              child: ListTile(
                                                  leading: Icon(
                                                    Icons.drive_file_rename_outline,
                                                    color: Theme.of(context).brightness==Brightness.light?SystemTheme.accentColor.accent:null,
                                                  ),
                                                  dense:false,
                                                  title: Text(
                                                    "Rename",
                                                    style: TextStyle(
                                                      color: Theme.of(context).brightness==Brightness.light?SystemTheme.accentColor.accent:null,
                                                    ),
                                                  )),
                                              onTap: () async {
                                                _renameItemFocus.requestFocus();
                                                setState(() {
                                                  _renameFieldController.text=snapshot.data![index].itemName;
                                                });
                                              },
                                            ),
                                            PopupMenuItem(
                                              child: ListTile(
                                                  leading: Icon(
                                                    FontAwesomeIcons.copy,
                                                    color: Theme.of(context).brightness==Brightness.light?SystemTheme.accentColor.accent:null,
                                                  ),
                                                  dense:false,
                                                  title: Text(
                                                    "Copy",
                                                    style: TextStyle(
                                                      color: Theme.of(context).brightness==Brightness.light?SystemTheme.accentColor.accent:null,
                                                    ),
                                                  )),
                                              onTap: () {
                                                addFileTransferJob(
                                                    FileTransferType.copy,
                                                    snapshot.data![index].itemName
                                                );
                                              },
                                            ),
                                            PopupMenuItem(
                                              child: ListTile(
                                                  leading: Icon(
                                                    FontAwesomeIcons.cut,
                                                    color: Theme.of(context).brightness==Brightness.light?SystemTheme.accentColor.accent:null,
                                                  ),
                                                  dense:false,
                                                  title: Text(
                                                    "Cut",
                                                    style: TextStyle(
                                                      color: Theme.of(context).brightness==Brightness.light?SystemTheme.accentColor.accent:null,
                                                    ),
                                                  )),
                                              onTap: () {
                                                addFileTransferJob(
                                                    FileTransferType.move,
                                                    snapshot.data![index].itemName
                                                );
                                              },
                                            ),
                                            PopupMenuItem(
                                              child: ListTile(
                                                  leading: Icon(
                                                    FontAwesomeIcons.trash,
                                                    color: Theme.of(context).brightness==Brightness.light?SystemTheme.accentColor.accent:null,
                                                  ),
                                                  dense:false,
                                                  title: Text(
                                                    "Delete",
                                                    style: TextStyle(
                                                      color: Theme.of(context).brightness==Brightness.light?SystemTheme.accentColor.accent:null,
                                                    ),
                                                  )),
                                              onTap: () {
                                                adbService.deleteItem(
                                                    itemPath: _currentPath+snapshot.data![index].itemName,
                                                    beforeExecution: (){
                                                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                                          duration: const Duration(seconds: 2),
                                                          content: Row(
                                                            children: [
                                                              CircularProgressIndicator(
                                                                valueColor: AlwaysStoppedAnimation<Color?>(SystemTheme.accentColor.accent),
                                                              ),
                                                              const SizedBox(
                                                                width: 12,
                                                              ),
                                                              Text("Deleting ${snapshot.data![index].itemName}"),
                                                            ],
                                                          )));
                                                      ScaffoldMessenger.of(context).deactivate();
                                                    },
                                                    onSuccess: (){
                                                      super.setState(() {});
                                                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(duration: const Duration(seconds: 2),content: Text("${snapshot.data![index].itemName} deleted successfully")));
                                                      ScaffoldMessenger.of(context).deactivate();
                                                    }
                                                );
                                              },
                                            ),
                                            if(fileContentTypeSnapshot.data==FileContentTypes.directory)...[
                                              PopupMenuItem(
                                                child: ListTile(
                                                    leading: Icon(
                                                      Icons.perm_media_rounded,
                                                      color: Theme.of(context).brightness==Brightness.light?SystemTheme.accentColor.accent:null,
                                                    ),
                                                    dense:false,
                                                    title: Text(
                                                      "Include in Media Scanner",
                                                      style: TextStyle(
                                                        color: Theme.of(context).brightness==Brightness.light?SystemTheme.accentColor.accent:null,
                                                      ),
                                                    )),
                                                onTap: () async {
                                                  if(await adbService.includeInMediaScanner("$_currentPath${snapshot.data![index].itemName}/")==0){
                                                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Successfully included in media scanner"),));
                                                  }else{
                                                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Failed to include in media scanner"),));
                                                  }
                                                },
                                              ),
                                              PopupMenuItem(
                                                child: ListTile(
                                                    leading: Icon(
                                                      Icons.remove_circle_rounded,
                                                      color: Theme.of(context).brightness==Brightness.light?SystemTheme.accentColor.accent:null,
                                                    ),
                                                    dense:false,
                                                    title: Text(
                                                      "Exclude from Media Scanner",
                                                      style: TextStyle(
                                                        color: Theme.of(context).brightness==Brightness.light?SystemTheme.accentColor.accent:null,
                                                      ),
                                                    )),
                                                onTap: () async {
                                                  if(await adbService.excludeFromMediaScanner(_currentPath+snapshot.data![index].itemName+"/")==0){
                                                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Successfully excluded from media scanner"),));
                                                  }else{
                                                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Failed to exclude from media scanner"),));
                                                  }
                                                },
                                              ),
                                            ]
                                          ],
                                        );
                                      },
                                    ),
                                  ],
                                ),
                              );
                            }
                            return Row(
                              children: [
                                SizedBox.fromSize(
                                  size: const Size(25, 0),
                                ),
                                FutureIcon(iconData: getFileIconByType(snapshot.data![index].itemContentType)),
                                SizedBox.fromSize(
                                  size: const Size(25, 0),
                                ),
                                Expanded(
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: TextField(
                                          enabled: true,
                                          focusNode: _renameItemFocus,
                                          controller: _renameFieldController,
                                          decoration: InputDecoration(
                                            border: OutlineInputBorder(
                                                borderRadius: BorderRadius.circular(10)
                                            ),
                                            focusColor: SystemTheme.accentColor.accent,
                                            hintText: "New name here",
                                            hintStyle: TextStyle(
                                                color: Colors.grey[500]
                                            ),
                                          ),
                                          onSubmitted: (value){
                                            renameItem(snapshot.data![index].itemName,_renameFieldController.text);
                                          },
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.check_circle,color: Colors.green,),
                                        splashRadius: 8,
                                        onPressed: () {
                                          renameItem(snapshot.data![index].itemName,_renameFieldController.text);
                                        },
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.cancel,color: Colors.red,),
                                        splashRadius: 8,
                                        onPressed: () {
                                          setState(() {
                                            _renameFieldController.text="";
                                          });
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            );
                          }
                        );
                      }),
                );
              },
            ),
          ),
      ],
    );
  }
}

class ClipboardChip extends StatelessWidget {
  final String itemName;
  final int jobIndex;
  final FileTransferType fileTransferType;
  final Function transferFile;
  final BuildContext parentContext;
  const ClipboardChip(
      {super.key,
      required this.itemName,
      required this.jobIndex,
      required this.fileTransferType,
      required this.transferFile,
      required this.parentContext});

  @override
  Widget build(BuildContext context) {
    int colorIndex = itemName.codeUnitAt(0) % clipboardChipColors.length;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 200),
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Chip(
          shape: RoundedRectangleBorder(
            side: BorderSide(color: clipboardChipColors[colorIndex]),
            borderRadius: BorderRadius.circular(20),
          ),
          onDeleted: () {
            transferFile(fileTransferType, jobIndex, parentContext);
          },
          deleteButtonTooltipMessage: "Paste here",
          deleteIcon: Icon(
            fileTransferType == FileTransferType.move ? FontAwesomeIcons.cut : FontAwesomeIcons.copy,
            size: 18,
            color: clipboardChipColors[colorIndex],
          ),
          materialTapTargetSize: MaterialTapTargetSize.padded,
          labelStyle: TextStyle(color: clipboardChipColors[colorIndex]),
          // backgroundColor: Colors.pink,
          label: Text(
            itemName,
            overflow: TextOverflow.fade,
          ),
        ),
      ),
    );
  }
}


class FutureIcon extends StatelessWidget {

  final Future<IconData> iconData;
  const FutureIcon({super.key,required this.iconData});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: iconData,
      builder: (BuildContext context, AsyncSnapshot<IconData> snapshot){
        if(!snapshot.hasData){
          return const CircularProgressIndicator();
        }
        return Icon(snapshot.data,color: SystemTheme.accentColor.accent,);
      },
    );
  }
}

