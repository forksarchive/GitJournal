/*
 * SPDX-FileCopyrightText: 2019-2021 Vishesh Handa <me@vhanda.in>
 *
 * SPDX-License-Identifier: Apache-2.0
 */

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:collection/collection.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:provider/provider.dart';

import 'package:gitjournal/core/image.dart' as core;
import 'package:gitjournal/core/md_yaml_doc.dart';
import 'package:gitjournal/core/note.dart';
import 'package:gitjournal/core/note_storage.dart';
import 'package:gitjournal/core/notes_folder.dart';
import 'package:gitjournal/core/notes_folder_fs.dart';
import 'package:gitjournal/core/views/inline_tags_view.dart';
import 'package:gitjournal/editors/checklist_editor.dart';
import 'package:gitjournal/editors/common.dart';
import 'package:gitjournal/editors/common_types.dart';
import 'package:gitjournal/editors/journal_editor.dart';
import 'package:gitjournal/editors/markdown_editor.dart';
import 'package:gitjournal/editors/note_editor_selector.dart';
import 'package:gitjournal/editors/org_editor.dart';
import 'package:gitjournal/editors/raw_editor.dart';
import 'package:gitjournal/error_reporting.dart';
import 'package:gitjournal/generated/locale_keys.g.dart';
import 'package:gitjournal/logger/logger.dart';
import 'package:gitjournal/repository.dart';
import 'package:gitjournal/settings/settings.dart';
import 'package:gitjournal/utils/utils.dart';
import 'package:gitjournal/widgets/folder_selection_dialog.dart';
import 'package:gitjournal/widgets/note_delete_dialog.dart';
import 'package:gitjournal/widgets/note_tag_editor.dart';
import 'package:gitjournal/widgets/rename_dialog.dart';

class ShowUndoSnackbar {}

class NoteEditor extends StatefulWidget {
  final Note? note;
  final NotesFolderFS notesFolder;
  final NotesFolder parentFolderView;
  final EditorType? defaultEditorType;

  final String? existingText;
  final List<String>? existingImages;

  final Map<String, dynamic>? newNoteExtraProps;
  final String? newNoteFileName;
  final bool editMode;

  final String? highlightString;

  NoteEditor.fromNote(
    this.note,
    this.parentFolderView, {
    this.editMode = false,
    this.highlightString,
  })  : notesFolder = note!.parent,
        defaultEditorType = null,
        existingText = null,
        existingImages = null,
        newNoteFileName = null,
        newNoteExtraProps = null;

  const NoteEditor.newNote(
    this.notesFolder,
    this.parentFolderView,
    this.defaultEditorType, {
    required String this.existingText,
    required List<String> this.existingImages,
    this.newNoteExtraProps = const {},
    this.newNoteFileName,
  })  : note = null,
        editMode = true,
        highlightString = null;

  @override
  NoteEditorState createState() {
    if (note == null) {
      return NoteEditorState.newNote(
        notesFolder,
        existingText!,
        existingImages!,
        newNoteExtraProps!,
        newNoteFileName,
      );
    } else {
      return NoteEditorState.fromNote(note);
    }
  }
}

class NoteEditorState extends State<NoteEditor>
    with WidgetsBindingObserver
    implements EditorCommon {
  Note? note;
  EditorType editorType = EditorType.Markdown;
  MdYamlDoc originalNoteData = MdYamlDoc();

  final _rawEditorKey = GlobalKey<RawEditorState>();
  final _markdownEditorKey = GlobalKey<MarkdownEditorState>();
  final _checklistEditorKey = GlobalKey<ChecklistEditorState>();
  final _journalEditorKey = GlobalKey<JournalEditorState>();
  final _orgEditorKey = GlobalKey<OrgEditorState>();

  bool get _isNewNote {
    return widget.note == null;
  }

  NoteEditorState.newNote(
    NotesFolderFS folder,
    String existingText,
    List<String> existingImages,
    Map<String, dynamic> extraProps,
    String? fileName,
  ) {
    note = Note.newNote(folder, extraProps: extraProps, fileName: fileName);
    if (existingText.isNotEmpty) {
      note!.apply(body: existingText);
    }

    if (existingImages.isNotEmpty) {
      for (var imagePath in existingImages) {
        () async {
          try {
            var image = await core.Image.copyIntoFs(note!.parent, imagePath);
            note!.apply(body: note!.body + image.toMarkup(note!.fileFormat));
          } catch (e, st) {
            Log.e("New Note Existing Image", ex: e, stacktrace: st);
          }
        }();
      }
    }
  }

  NoteEditorState.fromNote(this.note) {
    originalNoteData = MdYamlDoc.from(note!.data);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance!.addObserver(this);
    var note = this.note!;

    if (widget.defaultEditorType != null) {
      editorType = widget.defaultEditorType!;
    } else {
      switch (note.type) {
        case NoteType.Journal:
          editorType = EditorType.Journal;
          break;
        case NoteType.Checklist:
          editorType = EditorType.Checklist;
          break;
        case NoteType.Org:
          editorType = EditorType.Org;
          break;
        case NoteType.Unknown:
          editorType = widget.notesFolder.config.defaultEditor.toEditorType();
          break;
      }
    }

    // Org files
    if (note.fileFormat == NoteFileFormat.OrgMode &&
        editorType == EditorType.Markdown) {
      editorType = EditorType.Org;
    }

    // Txt files
    if (note.fileFormat == NoteFileFormat.Txt &&
        editorType == EditorType.Markdown) {
      editorType = EditorType.Raw;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance!.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    Log.i("Note Edit State: $state");

    if (state != AppLifecycleState.resumed) {
      var note = _getNoteFromEditor();
      if (!_noteModified(note)) return;

      Log.d("App Lost Focus - saving note");
      var repo = Provider.of<GitJournalRepo>(context, listen: false);
      repo.saveNoteToDisk(note).then((r) {
        if (r.isFailure) {
          Log.e("Failed to save note", ex: r.error, stacktrace: r.stackTrace);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        var savedNote = await _saveNote(_getNoteFromEditor());
        return savedNote;
      },
      child: widget.note != null
          ? Hero(tag: widget.note!.filePath, child: _getEditor())
          : _getEditor(),
    );
  }

  Widget _getEditor() {
    var note = this.note!;

    switch (editorType) {
      case EditorType.Markdown:
        return MarkdownEditor(
          key: _markdownEditorKey,
          note: note,
          parentFolder: widget.parentFolderView,
          noteModified: _noteModified(note),
          editMode: widget.editMode,
          highlightString: widget.highlightString,
          theme: Theme.of(context),
          common: this,
        );
      case EditorType.Raw:
        return RawEditor(
          key: _rawEditorKey,
          note: note,
          noteModified: _noteModified(note),
          editMode: widget.editMode,
          highlightString: widget.highlightString,
          theme: Theme.of(context),
          common: this,
        );
      case EditorType.Checklist:
        return ChecklistEditor(
          key: _checklistEditorKey,
          note: note,
          noteModified: _noteModified(note),
          editMode: widget.editMode,
          highlightString: widget.highlightString,
          theme: Theme.of(context),
          common: this,
        );
      case EditorType.Journal:
        return JournalEditor(
          key: _journalEditorKey,
          note: note,
          noteModified: _noteModified(note),
          editMode: widget.editMode,
          highlightString: widget.highlightString,
          theme: Theme.of(context),
          common: this,
        );
      case EditorType.Org:
        return OrgEditor(
          key: _orgEditorKey,
          note: note,
          noteModified: _noteModified(note),
          editMode: widget.editMode,
          highlightString: widget.highlightString,
          theme: Theme.of(context),
          common: this,
        );
    }
  }

  @override
  void noteEditorChooserSelected(Note _note) async {
    var newEditorType = await showDialog<EditorType>(
      context: context,
      builder: (BuildContext context) {
        return NoteEditorSelector(editorType, _note.fileFormat!);
      },
    );

    if (newEditorType != null) {
      setState(() {
        note = _note;
        editorType = newEditorType;
      });
    }
  }

  @override
  void exitEditorSelected(Note note) async {
    var saved = await _saveNote(note);
    if (saved) {
      Navigator.pop(context);
    }
  }

  @override
  void renameNote(Note _note) async {
    var note = this.note!;
    var fileName = await showDialog(
      context: context,
      builder: (_) => RenameDialog(
        oldPath: note.filePath,
        inputDecoration: tr(LocaleKeys.widgets_NoteEditor_fileName),
        dialogTitle: tr(LocaleKeys.widgets_NoteEditor_renameFile),
      ),
    );
    if (fileName is String) {
      if (_isNewNote) {
        setState(() {
          this.note = _note;
          note.parent.rename(fileName);
        });
        return;
      }
      var container = context.read<GitJournalRepo>();
      container.renameNote(note, fileName);
    }
  }

  @override
  void deleteNote(Note note) async {
    if (_isNewNote && !_noteModified(note)) {
      Navigator.pop(context);
      return;
    }

    var settings = Provider.of<Settings>(context, listen: false);
    bool shouldDelete = true;
    if (settings.confirmDelete) {
      shouldDelete = await showDialog(
        context: context,
        builder: (context) => NoteDeleteDialog(),
      );
    }
    if (shouldDelete == true) {
      if (!_isNewNote) {
        var stateContainer = context.read<GitJournalRepo>();
        stateContainer.removeNote(note);
      }

      if (_isNewNote) {
        Navigator.pop(context); // Note Editor
      } else {
        Navigator.pop(context, ShowUndoSnackbar()); // Note Editor
      }
    }
  }

  bool _noteModified(Note note) {
    if (_isNewNote) {
      return note.title.isNotEmpty || note.body.isNotEmpty;
    }

    if (note.data != originalNoteData) {
      var newSimplified = MdYamlDoc.from(note.data);
      newSimplified.props.remove(note.noteSerializer.settings.modifiedKey);
      newSimplified.body = newSimplified.body.trim();

      var originalSimplified = MdYamlDoc.from(originalNoteData);
      originalSimplified.props.remove(note.noteSerializer.settings.modifiedKey);
      originalSimplified.body = originalSimplified.body.trim();

      bool hasBeenModified = newSimplified != originalSimplified;
      if (hasBeenModified) {
        Log.d("Note modified");
        // Log.d("Original: $originalSimplified");
        // Log.d("New: $newSimplified");
        return true;
      }
    }
    return false;
  }

  // Returns bool indicating if the note was successfully saved
  Future<bool> _saveNote(Note note) async {
    if (!_noteModified(note)) return true;

    Log.d("Note modified - saving");
    try {
      var stateContainer = context.read<GitJournalRepo>();
      _isNewNote
          ? await stateContainer.addNote(note)
          : await stateContainer.updateNote(note);
    } catch (e, stackTrace) {
      logException(e, stackTrace);
      Clipboard.setData(ClipboardData(text: NoteStorage.serialize(note)));

      await showAlertDialog(
        context,
        tr(LocaleKeys.editors_common_saveNoteFailed_title),
        tr(LocaleKeys.editors_common_saveNoteFailed_message),
      );
      return false;
    }

    return true;
  }

  Note _getNoteFromEditor() {
    switch (editorType) {
      case EditorType.Markdown:
        return _markdownEditorKey.currentState!.getNote();
      case EditorType.Raw:
        return _rawEditorKey.currentState!.getNote();
      case EditorType.Checklist:
        return _checklistEditorKey.currentState!.getNote();
      case EditorType.Journal:
        return _journalEditorKey.currentState!.getNote();
      case EditorType.Org:
        return _orgEditorKey.currentState!.getNote();
    }
  }

  @override
  void moveNoteToFolderSelected(Note note) async {
    var destFolder = await showDialog<NotesFolderFS>(
      context: context,
      builder: (context) => FolderSelectionDialog(),
    );
    if (destFolder != null) {
      if (_isNewNote) {
        note.parent = destFolder;
        setState(() {});
      } else {
        var stateContainer = context.read<GitJournalRepo>();
        stateContainer.moveNote(note, destFolder);
      }
    }
  }

  @override
  Future<void> discardChanges(Note note) async {
    if (!_isNewNote) {
      var stateContainer = context.read<GitJournalRepo>();
      stateContainer.discardChanges(note);
    }

    Navigator.pop(context);
  }

  @override
  void editTags(Note _note) async {
    final rootFolder = Provider.of<NotesFolderFS>(context, listen: false);
    var inlineTagsView = InlineTagsProvider.of(context);
    var allTags = await rootFolder.getNoteTagsRecursively(inlineTagsView);

    var route = MaterialPageRoute(
      builder: (context) => NoteTagEditor(
        selectedTags: note!.tags,
        allTags: allTags,
      ),
      settings: const RouteSettings(name: '/editTags/'),
    );
    var newTags = await Navigator.of(context).push(route);
    assert(newTags != null);

    Function eq = const SetEquality().equals;
    if (!eq(note!.tags, newTags)) {
      setState(() {
        Log.i("Settings tags to: $newTags");
        note!.apply(tags: newTags);
      });
    }
  }
}
