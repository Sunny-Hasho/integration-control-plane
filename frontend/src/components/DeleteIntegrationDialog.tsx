/**
 * Copyright (c) 2026, WSO2 LLC. (https://www.wso2.com).
 *
 * WSO2 LLC. licenses this file to you under the Apache License,
 * Version 2.0 (the "License"); you may not use this file except
 * in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing,
 * software distributed under the License is distributed on an
 * "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 * KIND, either express or implied. See the License for the
 * specific language governing permissions and limitations
 * under the License.
 */

import { useState } from 'react';
import { Dialog, DialogTitle, DialogContent, DialogContentText, DialogActions, Alert, Button, TextField } from '@wso2/oxygen-ui';
import { useDeleteComponent } from '../api/mutations';
import type { GqlComponent } from '../api/queries';

interface DeleteIntegrationDialogProps {
  component: GqlComponent;
  orgHandler: string;
  projectId: string;
  onClose: () => void;
  onDeleted?: () => void;
}

export default function DeleteIntegrationDialog({ component, orgHandler, projectId, onClose, onDeleted }: DeleteIntegrationDialogProps) {
  const [confirmation, setConfirmation] = useState('');
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const mutation = useDeleteComponent();
  const confirmed = confirmation === component.displayName;

  const handleDelete = () => {
    setErrorMessage(null);
    mutation.mutate(
      { orgHandler, componentId: component.id, projectId },
      {
        onSuccess: (data) => {
          if (data.canDelete) {
            onDeleted?.();
            onClose();
          } else {
            setErrorMessage(data.message || 'Cannot delete integration. Please try again.');
          }
        },
        onError: (error) => {
          setErrorMessage(error.message || 'Failed to delete integration. Please try again.');
        },
      },
    );
  };

  return (
    <Dialog open onClose={onClose} maxWidth="sm" fullWidth>
      <DialogTitle>
        Are you sure you want to remove the integration &lsquo;<strong>{component.displayName}</strong>&rsquo;?
      </DialogTitle>
      <DialogContent>
        <DialogContentText sx={{ mb: 2 }}>This action will be irreversible and all related details will be lost. Please type in the integration name below to confirm.</DialogContentText>
        {errorMessage && (
          <Alert severity="error" sx={{ mb: 2 }}>
            {errorMessage}
          </Alert>
        )}
        <TextField autoFocus fullWidth placeholder="Enter integration name to confirm" value={confirmation} onChange={(e) => setConfirmation(e.target.value)} />
      </DialogContent>
      <DialogActions>
        <Button variant="outlined" onClick={onClose}>
          Cancel
        </Button>
        <Button variant="contained" color="error" disabled={!confirmed || mutation.isPending} onClick={handleDelete}>
          Delete
        </Button>
      </DialogActions>
    </Dialog>
  );
}
