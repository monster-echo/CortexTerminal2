'use client'

import { z } from 'zod'
import { useForm } from 'react-hook-form'
import { zodResolver } from '@hookform/resolvers/zod'
import { useMutation, useQueryClient } from '@tanstack/react-query'
import { useTranslation } from 'react-i18next'
import { toast } from 'sonner'
import { Button } from '@/components/ui/button'
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog'
import {
  Form,
  FormField,
  FormItem,
  FormLabel,
  FormMessage,
} from '@/components/ui/form'
import { SelectDropdown } from '@/components/select-dropdown'
import { createConsoleApi } from '@/services/console-api'
import { useAuthStore } from '@/stores/auth-store'
import { roles } from '../data/data'
import { type User } from '../data/schema'

const consoleApi = createConsoleApi({
  getToken: () => useAuthStore.getState().auth.accessToken,
  onUnauthorized: () => useAuthStore.getState().auth.reset(),
  onTokenRefreshed: (newToken) =>
    useAuthStore.getState().auth.setAccessToken(newToken),
})

const formSchema = z.object({
  role: z.string().min(1, 'Role is required.'),
})

type UserActionForm = z.infer<typeof formSchema>

type UserActionDialogProps = {
  currentRow?: User
  open: boolean
  onOpenChange: (open: boolean) => void
}

export function UsersActionDialog({
  currentRow,
  open,
  onOpenChange,
}: UserActionDialogProps) {
  const { t } = useTranslation()
  const queryClient = useQueryClient()
  const isEdit = !!currentRow
  const form = useForm<UserActionForm>({
    resolver: zodResolver(formSchema),
    defaultValues: isEdit
      ? { role: currentRow.role }
      : { role: '' },
  })

  const updateMutation = useMutation({
    mutationFn: (values: UserActionForm & { userId: string }) =>
      consoleApi.updateUser(values.userId, { role: values.role as User['role'] }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['users'] })
      toast.success(t('common.save'))
      form.reset()
      onOpenChange(false)
    },
    onError: (error: Error) => {
      toast.error(error.message)
    },
  })

  const onSubmit = (values: UserActionForm) => {
    if (currentRow) {
      updateMutation.mutate({ ...values, userId: currentRow.id })
    }
  }

  return (
    <Dialog
      open={open}
      onOpenChange={(state) => {
        form.reset()
        onOpenChange(state)
      }}
    >
      <DialogContent className='sm:max-w-md'>
        <DialogHeader className='text-start'>
          <DialogTitle>{t('users.actions.editRole')}</DialogTitle>
          <DialogDescription>
            {isEdit && (
              <span>
                Update role for <strong>{currentRow.name}</strong> ({currentRow.email}).
              </span>
            )}
          </DialogDescription>
        </DialogHeader>
        <Form {...form}>
          <form
            id='user-action-form'
            onSubmit={form.handleSubmit(onSubmit)}
            className='space-y-4'
          >
            <FormField
              control={form.control}
              name='role'
              render={({ field }) => (
                <FormItem>
                  <FormLabel>Role</FormLabel>
                  <SelectDropdown
                    defaultValue={field.value}
                    onValueChange={field.onChange}
                    placeholder='Select a role'
                    items={roles.map(({ label, value }) => ({
                      label,
                      value,
                    }))}
                  />
                  <FormMessage />
                </FormItem>
              )}
            />
          </form>
        </Form>
        <DialogFooter>
          <Button
            type='submit'
            form='user-action-form'
            disabled={updateMutation.isPending}
          >
            {t('common.save')}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
